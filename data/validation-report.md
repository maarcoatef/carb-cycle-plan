# Plan v2 – import validation report

Source: `28-day-carb-cycling-meal-plan.pdf` (sha256 `a81419d2abc04d825031e0e093815f745396e97c22c4dbf5609cf56e54658e99`) · 13/13 checks passed

## Counts
- Weeks: 4
- Days: 28
- Food items (meals + iced coffee): 292
- Reference foods: 32
- Flags: 48 (see data/_flags.json; mostly unknown fiber)

## Checks
| Result | Check | Detail |
|---|---|---|
| PASS | 1. Exactly 4 weeks / 28 days / 7 per week | 28 days |
| PASS | 2. Day numbers 1..28 in order |  |
| PASS | 3. Carb type present on every day |  |
| PASS | 4. Carb cycle identical in all 4 weeks (Sat Mod, Sun Low, Mon Low, Tue Mod, Wed Low, Thu Mod, Fri High) | ['Moderate', 'Low', 'Low', 'Moderate', 'Low', 'Moderate', 'High'] |
| PASS | 5. Every day has breakfast, lunch, dinner, snack and an iced coffee |  |
| PASS | 6. Daily total printed on every day |  |
| PASS | 7. No duplicate item ids | 292 items |
| PASS | 8. Meal totals: items (+ iced coffee for the snack section) equal the printed MEAL TOTAL (±1 kcal / ±0.15 g) | [] |
| PASS | 9. Daily totals: sum of all items equals the printed DAILY TOTAL (±1.5 kcal / ±0.3 g) | [] |
| PASS | 10. Carbs of each day vs. carb-type target (Low 80 / Moderate 140 / High 210 g) | [] |
| PASS | 11. Reference table has 32 foods | 32 |
| PASS | 12. Every food name exists in the reference table | [] |
| PASS | 13. Every item equals the reference food scaled by quantity (kcal ±1, macros ±0.2) | 0 differences: [] |
