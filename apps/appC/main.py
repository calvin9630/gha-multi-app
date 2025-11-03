import time, datetime
def main():
    now = datetime.datetime.now().astimezone()
    print(f"[AppC] Tick at {now:%Y-%m-%d %H:%M:%S %Z}")
    time.sleep(1)
    print("[AppC] Done.")
if __name__ == "__main__":
    main()
