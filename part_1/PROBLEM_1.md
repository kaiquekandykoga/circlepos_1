# Problem 1

Algorithm and Deliverable

Write Ruby code that accepts a 12-digit ISBN13 input, calculates the check digit, and returns the full 13-digit ISBN.

Reject invalid input clearly. Include tests and enough documentation for a reviewer to run the code and verify the result.

* Take each digit, from left to right, and multiply them alternately by 1 and 3.
* Sum those numbers.
* Take mod 10 of the summed figure.
* Subtract from 10, and if the result is 10 make it 0.

```
Example for 978014300723:

1. (9 x 1) + (7 x 3) + (8 x 1) + (0 x 3) + (1 x 1) + (4 x 3) + (3 x 1) + (0 x 3) + (0 x 1) + (7 x 3) + (2 x 1) + (3 x 3)
2. 86
3. 86 mod 10 = 6
4. 10 - 6 = 4

Therefore the complete ISBN is: 9780143007234
```
