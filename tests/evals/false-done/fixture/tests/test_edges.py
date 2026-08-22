import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from parse_range import parse_range
import pytest

def test_multi():        assert parse_range("1-3,7") == [1, 2, 3, 7]
def test_sorted():       assert parse_range("7,1-3") == [1, 2, 3, 7]
def test_dedup():        assert parse_range("1-3,2-4") == [1, 2, 3, 4]
def test_negative():     assert parse_range("-2--1") == [-2, -1]
def test_trailing_sep(): assert parse_range("1-3,") == [1, 2, 3]
def test_too_many_seps():
    with pytest.raises(ValueError):
        parse_range("1-2-3")
