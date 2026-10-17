"""入口：没有参数（或 --agent）时进菜单栏，其余当命令行用。"""

import sys


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)

    # 从 Finder 启动时系统会塞一个 -psn_... 参数
    args = [a for a in args if not a.startswith("-psn_")]

    if not args or args[0] in ("--agent", "--ui"):
        from . import app

        # 登录自启时（--agent）不弹窗口，只留 Dock 图标和菜单栏，免得每次开机都蹦一下
        app.run(with_status_item=True, show_window=(args[:1] != ["--agent"]))
        return 0

    if args[0] in ("--version", "-V", "version"):
        from . import VERSION

        print(f"Luma {VERSION}")
        return 0

    from . import cli

    return cli.main(args)


if __name__ == "__main__":
    sys.exit(main())
