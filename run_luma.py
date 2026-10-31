"""py2app 的入口脚本。

不能直接拿 luma/__main__.py 当入口：它用的是包内相对导入，
被 py2app 当成顶层脚本执行后会失败。
"""

import sys

from luma.__main__ import main

if __name__ == "__main__":
    sys.exit(main())
