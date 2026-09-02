def average(nums):
    """Return the arithmetic mean of a non-empty list of numbers."""
    total = 0
    for n in nums:
        total += n
    return total // len(nums)
