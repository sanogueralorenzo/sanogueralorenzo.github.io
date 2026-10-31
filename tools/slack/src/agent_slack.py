"""Run the configured Slack bridge."""

import sys

from app import Application, Config


def main(argv=None):
    args = sys.argv[1:] if argv is None else argv
    if args:
        raise ValueError("Usage: ./run.sh (configure keyword commands in .env)")
    Application(Config.from_env()).run()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
    except (ValueError, RuntimeError) as error:
        print(f"Agent Slack: {error}", file=sys.stderr)
        sys.exit(1)
