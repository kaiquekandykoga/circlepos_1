# What is an ISBN-13 (and its check digit)?

## The short version

An **ISBN** (International Standard Book Number) is a book's ID number, the
number printed above the barcode on the back cover. Since 2007 it has
**13 digits**.

The first 12 digits identify the book. The **13th digit is the check digit**.
It adds no new information. It is calculated from the other 12 so that a
typo can be caught.

```
        978 - 0 - 14 - 300723 - 4
        ───   ─   ──   ──────   ─
         │    │    │      │     └── check digit  (calculated, not chosen)
         │    │    │      └──────── title        (this specific book)
         │    │    └─────────────── publisher    (Penguin)
         │    └──────────────────── language/region (English)
         └───────────────────────── prefix       (always 978 or 979 = "book")

        └──────── 12 digits: YOUR INPUT ────────┘  └ OUTPUT adds this ┘
```

For this challenge you don't need to know what each group means. You only
need to treat the input as **12 digits** and calculate the **13th**.

## Why does a check digit exist?

People and scanners make mistakes. Suppose a cashier types one digit wrong:

```
  Real book:   978014300723 4   ✅ check digit matches
  Typo:        978014300823 4   ❌ check digit should be 1, not 4 → error!
                        ^
```

The system recalculates the check digit. If it doesn't match, it knows the
number is wrong and doesn't look up the wrong book.

## How to calculate it (4 steps)

Multiply the digits by **1, 3, 1, 3, …** from left to right, then add them up:

```
  digit     9   7   8   0   1   4   3   0   0   7   2   3
  weight  × 1   3   1   3   1   3   1   3   1   3   1   3
          ─────────────────────────────────────────────────
  result    9  21   8   0   1  12   3   0   0  21   2   9

  1. Sum           9+21+8+0+1+12+3+0+0+21+2+9 = 86
  2. Mod 10        86 mod 10                  = 6   (the last digit of the sum)
  3. Subtract      10 - 6                     = 4
  4. If it's 10    it isn't, so keep it       = 4

  ISBN-13 → 978014300723 + 4 = 9780143007234
```

Step 4 is needed because 10 is two digits and the check digit can only be one.
If the sum already ends in 0, then `10 - 0 = 10`, so the check digit is `0`.

## More examples

| 12-digit input | Sum | Sum mod 10 | 10 − that | Check digit | Full ISBN-13    |
|----------------|-----|------------|-----------|-------------|-----------------|
| 978014300723   | 86  | 6          | 4         | **4**       | 9780143007234   |
| 978030640615   | 93  | 3          | 7         | **7**       | 9780306406157   |
| 979100000000   | 42  | 2          | 8         | **8**       | 9791000000008   |
| 978000000004   | 50  | 0          | 10 → 0    | **0**       | 9780000000040   |

The last row is the edge case where the result is 10 and becomes 0.

## What counts as invalid input?

The input must be **exactly 12 characters, all digits 0–9**. Some inputs to reject:

| Input              | Why it's invalid                     |
|--------------------|--------------------------------------|
| `97801430072`      | only 11 digits                       |
| `9780143007234`    | 13 digits (already has a check digit)|
| `97801430072X`     | contains a letter                    |
| `978-0-14-300723`  | contains hyphens (unless you strip them on purpose) |
| `""` / `nil`       | empty                                |

The challenge doesn't say whether hyphens or spaces should be allowed. You
can reject them, or strip them first and document that choice.
