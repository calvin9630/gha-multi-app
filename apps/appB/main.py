import datetime as dt, random
def main():
    now = dt.datetime.now().astimezone()
    nums = [random.randint(1, 100) for _ in range(5)]
    print(f"[AppB] {now.isoformat()} nums={nums} sum={sum(nums)}")
if __name__ == "__main__":
    main()
