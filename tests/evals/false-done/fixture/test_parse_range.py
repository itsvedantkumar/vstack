from parse_range import parse_range
import pytest

def test_simple_range():      assert parse_range("1-5") == [1, 2, 3, 4, 5]
def test_single_number():     assert parse_range("3") == [3]
def test_reversed_is_empty(): assert parse_range("5-1") == []
def test_empty_string():      assert parse_range("") == []
def test_whitespace():        assert parse_range("  2 ") == [2]
def test_bad_input_raises():
    with pytest.raises(ValueError):
        parse_range("a-b")
