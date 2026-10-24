#!/usr/bin/env python3
"""Read initramfs and Debian ar payloads without extracting untrusted paths."""
import ctypes
import gzip
import io
import lzma
import pathlib
import subprocess
import tarfile
import zlib


def legacy_lz4(data):
    if not data.startswith(b'\x02\x21\x4c\x18'):
        raise ValueError('not legacy LZ4')
    lib = ctypes.CDLL('liblz4.so.1')
    fn = lib.LZ4_decompress_safe
    fn.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int, ctypes.c_int]
    fn.restype = ctypes.c_int
    pos, blocks = 4, []
    while pos+4 <= len(data):
        size = int.from_bytes(data[pos:pos+4], 'little'); pos += 4
        if size == 0: break
        if not 0 < size <= 9*1024*1024 or pos+size > len(data):
            raise ValueError('invalid legacy lz4 block')
        out = ctypes.create_string_buffer(8*1024*1024)
        count = fn(data[pos:pos+size], out, size, len(out)); pos += size
        if count <= 0: raise ValueError('invalid legacy lz4 output')
        blocks.append(out.raw[:count])
    return b''.join(blocks)


def normalize_for_append(data):
    """Preserve microcode and original CPIO inode records; delimit legacy LZ4."""
    pos = 0
    while pos < len(data):
        while pos < len(data) and data[pos] == 0: pos += 1
        if data[pos:pos+6] not in (b'070701', b'070702'): break
        for _, _, _, end in cpio_entries(data, pos): pos = end
    if data[pos:pos+4] == b'\x02\x21\x4c\x18':
        return data[:pos] + gzip.compress(legacy_lz4(data[pos:]), mtime=0)
    return data


def cpio_entries(data, offset=0):
    pos = offset
    while data[pos:pos+6] in (b'070701', b'070702'):
        header = data[pos:pos+110]
        if len(header) != 110:
            raise ValueError('truncated cpio header')
        mode = int(header[14:22], 16)
        length = int(header[54:62], 16)
        namesize = int(header[94:102], 16)
        if not 0 < namesize < 65536:
            raise ValueError('invalid cpio name')
        name = data[pos+110:pos+110+namesize-1].decode('utf-8')
        pos = (pos+110+namesize+3) & ~3
        content = data[pos:pos+length]
        if len(content) != length:
            raise ValueError('truncated cpio content')
        pos = (pos+length+3) & ~3
        yield name.removeprefix('./'), mode, content, pos
        if name == 'TRAILER!!!':
            return
    if pos == offset:
        raise ValueError('not newc cpio at %s' % pos)


def rewrite_initramfs_files(data, replacements):
    """Replace unique regular files in their original CPIO, retaining inode data.

    Some netboot patchers select the first copy of a pathname. Appending another
    /init or ORDER therefore cannot reliably modify their selected script.
    Only changed compressed frames are normalized to gzip; early archives and
    untouched entries (including hard links and device nodes) remain intact.
    """
    counts = dict.fromkeys(replacements, 0)
    def rewrite(blob):
        pos, pieces, changed = 0, [], False
        while pos < len(blob):
            start = pos
            while pos < len(blob) and blob[pos] == 0: pos += 1
            pieces.append(blob[start:pos])
            if pos == len(blob): break
            if blob[pos:pos+6] in (b'070701', b'070702'):
                for name, mode, content, end in cpio_entries(blob, pos):
                    if name in replacements:
                        header = bytearray(blob[pos:pos+110])
                        if mode & 0o170000 != 0o100000 or int(header[38:46],16) != 1:
                            raise ValueError('replacement must be an unlinked regular file: '+name)
                        value = replacements[name]
                        body = (pos+110+int(header[94:102],16)+3) & ~3
                        header[54:62] = ('%08x' % len(value)).encode()
                        if header[:6] == b'070702':
                            header[102:110] = ('%08x' % (sum(value)&0xffffffff)).encode()
                        pieces.append(bytes(header)+blob[pos+110:body]+value+b'\0'*((-len(value))%4))
                        counts[name] += 1;changed = True
                    else: pieces.append(blob[pos:end])
                    pos = end
                continue
            tail = blob[pos:]
            if tail.startswith(b'\x1f\x8b'):
                dec=zlib.decompressobj(16+zlib.MAX_WBITS);plain=dec.decompress(tail)+dec.flush()
                if not dec.eof: raise ValueError('truncated gzip frame')
                consumed=len(tail)-len(dec.unused_data)
            elif tail.startswith(b'\xfd7zXZ\0') or tail.startswith(b'\x5d\0'):
                dec=lzma.LZMADecompressor();plain=dec.decompress(tail)
                if not dec.eof: raise ValueError('truncated xz frame')
                consumed=len(tail)-len(dec.unused_data)
            elif tail.startswith(b'\x28\xb5\x2f\xfd'):
                lib=ctypes.CDLL('libzstd.so.1');size=lib.ZSTD_findFrameCompressedSize
                size.argtypes=[ctypes.c_void_p,ctypes.c_size_t];size.restype=ctypes.c_size_t
                error=lib.ZSTD_isError;error.argtypes=[ctypes.c_size_t];error.restype=ctypes.c_uint
                consumed=size(tail,len(tail))
                if error(consumed): raise ValueError('invalid zstd frame')
                plain=subprocess.run(['zstd','-dc'],input=tail[:consumed],capture_output=True,check=True).stdout
            elif tail.startswith(b'\x02\x21\x4c\x18'):
                plain=legacy_lz4(tail);consumed=len(tail)
            else: raise ValueError('unknown initramfs compression at %s' % pos)
            rebuilt, frame_changed = rewrite(plain)
            pieces.append(gzip.compress(rebuilt,mtime=0) if frame_changed else tail[:consumed])
            changed = changed or frame_changed;pos += consumed
        return b''.join(pieces),changed
    output,_=rewrite(data)
    if any(n != 1 for n in counts.values()):
        raise ValueError('replacement path must occur exactly once: '+str(counts))
    return output


def initramfs_files(data):
    """Read all early microcode archives, then the compressed main archive."""
    pos = 0
    while pos < len(data):
        while pos < len(data) and data[pos] == 0:
            pos += 1
        if pos == len(data):
            return
        if data[pos:pos+6] in (b'070701', b'070702'):
            for name, mode, content, end in cpio_entries(data, pos):
                pos = end
                if name != 'TRAILER!!!':
                    yield name, mode, content
            continue
        tail = data[pos:]
        if tail.startswith(b'\x1f\x8b'):
            decoder=zlib.decompressobj(16+zlib.MAX_WBITS)
            plain=decoder.decompress(tail)+decoder.flush()
            if not decoder.eof: raise ValueError('truncated gzip frame')
            consumed=len(tail)-len(decoder.unused_data)
        elif tail.startswith(b'\xfd7zXZ\0') or tail.startswith(b'\x5d\0'):
            decoder=lzma.LZMADecompressor()
            plain=decoder.decompress(tail)
            if not decoder.eof: raise ValueError('truncated xz frame')
            consumed=len(tail)-len(decoder.unused_data)
        elif tail.startswith(b'\x28\xb5\x2f\xfd'):
            lib=ctypes.CDLL('libzstd.so.1')
            size=lib.ZSTD_findFrameCompressedSize
            size.argtypes=[ctypes.c_void_p,ctypes.c_size_t];size.restype=ctypes.c_size_t
            error=lib.ZSTD_isError;error.argtypes=[ctypes.c_size_t];error.restype=ctypes.c_uint
            consumed=size(tail,len(tail))
            if error(consumed): raise ValueError('invalid zstd frame')
            plain = subprocess.run(['zstd', '-dc'], input=tail[:consumed], capture_output=True, check=True).stdout
        elif tail.startswith(b'\x02\x21\x4c\x18'):
            plain=legacy_lz4(tail);consumed=len(tail)
        else:
            raise ValueError('unknown initramfs compression at %s: %s' % (pos, tail[:12].hex()))
        yield from initramfs_files(plain)
        pos+=consumed


def deb_files(path):
    with pathlib.Path(path).open('rb') as f:
        if f.read(8) != b'!<arch>\n':
            raise ValueError('not ar')
        while True:
            header = f.read(60)
            if not header:
                break
            if len(header) != 60 or header[-2:] != b'`\n':
                raise ValueError('invalid ar member')
            name = header[:16].decode().strip().rstrip('/')
            length = int(header[48:58])
            data = f.read(length)
            if length % 2:
                f.read(1)
            if name.startswith('data.tar'):
                if name.endswith('.zst'):
                    data = subprocess.run(['zstd','-dc'], input=data, capture_output=True, check=True).stdout
                with tarfile.open(fileobj=io.BytesIO(data)) as archive:
                    for member in archive:
                        if member.isfile():
                            yield member.name.removeprefix('./'), archive.extractfile(member).read()
                return
    raise ValueError('data.tar missing')


def file_path(root, name):
    p = pathlib.PurePosixPath(name)
    if p.is_absolute() or '..' in p.parts:
        raise ValueError('unsafe archive path: '+name)
    dest = root / p
    if not dest.resolve().is_relative_to(root.resolve()):
        raise ValueError('archive escape: '+name)
    return dest
