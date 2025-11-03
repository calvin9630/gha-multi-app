import datetime, os, socket
def main():
    now = datetime.datetime.now().astimezone()
    print(f"[AppA] Now: {now.isoformat()}")
    print(f"[AppA] Host={socket.gethostname()} User={os.getenv('USER')}")
    print(f"[AppA] Day-of-year={now.timetuple().tm_yday}")
    print("[AppA] DEMO_TOKEN set?" , bool(os.getenv("DEMO_TOKEN")))
if __name__ == "__main__":
    main()
