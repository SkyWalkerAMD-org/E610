#!/usr/bin/env python3
from pathlib import Path
import sys
from stage import checksums

root = Path(sys.argv[1])
expected = ['5.15.0-78-generic', '5.15.0-119-generic', '6.8.0-40-generic',
            '6.8.0-31-generic', '6.8.0-53-generic', '6.11.0-17-generic', '6.8.0-100-generic',
            '4.18.0-553.el8_10.x86_64', '5.14.0-427.13.1.el9_4.x86_64',
            '5.14.0-687.10.1.el9_8.0.1.x86_64', '3.10.0-1160.el7.x86_64', '3.10.0-1160.119.1.el7.x86_64']
for kernel in expected:
    assert f'E610_MEDIA_TEST_PASS kernel={kernel} ' in (root / f'media-{kernel}.log').read_text(), kernel
with (root / 'VALIDATION.zh-CN.md').open('a') as stream:
    stream.write('\n最终介质验证：12 个组合均通过只读 ISO、tar.gz 入口和 .run 校验、系统/内核选择、损坏包拒绝。需安装的组合另外通过重复安装和回退；原生支持组合确认未改动启动镜像。原有包的备份也验证保持不变。详见同目录 media-*.log。\n')
checksums(root)
print('E610_EXPANDED_RELEASE_VALIDATED')
