# Phase 1 – Nutrition import validation report

Source: `Carb Cycle - 4 Weeks Plan.pdf` · 17/18 checks passed

## Counts
- Weeks: 4
- Days: 28
- Meals (breakfast/lunch/dinner/snack): 112
- Daily iced coffee entries: 28 (56 coffee components)
- Food items in meals: 311 (+ 56 coffee components = 367 total)

## Checks
| Result | Check | Detail |
|---|---|---|
| PASS | 1. Exactly 4 weeks | 4 weeks |
| PASS | 2. Exactly 28 days | 28 days |
| PASS | 3. Each week has 7 days | [7, 7, 7, 7] |
| PASS | 3b. Day numbers 1..28 in order |  |
| PASS | 3c. Day/weekday headers equal PDF |  |
| PASS | 4. Carb type of every day equals PDF | Counter({'Moderate': 12, 'Low': 12, 'High': 4}) |
| PASS | 5. Every day has breakfast, lunch, dinner, snack |  |
| PASS | 13. Daily iced coffee on every day |  |
| PASS | 17. No skipped days/meals (28 days x 4 meals + 28 coffees) | 112 meals + 28 coffees |
| PASS | 16. No duplicate ids |  |
| PASS | 16b. No duplicate food within a meal |  |
| PASS | 3d. Carb cycle pattern identical in all 4 weeks (supports 7-day week grouping) | ['Moderate', 'Low', 'Low', 'Moderate', 'Low', 'Moderate', 'High'] |
| PASS | 3e. Weekday sequence continuous Sat..Fri |  |
| PASS | 6-12. Every food item (name, quantity, kcal, P, C, F, fiber) found verbatim in PDF | [] |
| PASS | 6b. Item count equals PDF item-line count | 311 items |
| **FAIL** | 14. Meal totals: sum of items equals PDF MEAL TOTAL (tol ±1 kcal / ±0.15 g, rounding) | 1 mismatches |
| PASS | 15. Daily totals: sum of items equals PDF DAILY TOTAL (tol ±2 kcal / ±0.5 g, rounding) | 0 mismatches |
| PASS | Coffee: PDF "previous" = DAILY TOTAL, previous+130 = updated, items 70+60 = 130 (no double count) | [] |

## PDF inconsistencies / items for review (nothing was silently corrected)

### A. Totals that do not add up (1)
- Week 4 Day 22 Breakfast: c items sum 30.9 vs PDF MEAL TOTAL 30.7

### B. Food items with NO fiber value printed in the PDF (115)
Stored as `null` and shown as "n/a"; counted as 0 only for the fiber *sum* (flagged in the UI).

| Week | Day | Meal | Food item |
|---|---|---|---|
| 1 | 1 | dinner | Greek yogurt, plain |
| 1 | 1 | dinner | Oats |
| 1 | 1 | dinner | Banana |
| 1 | 1 | snack | Gullon shortbread |
| 1 | 2 | dinner | Egg whites |
| 1 | 2 | dinner | Whole egg |
| 1 | 2 | dinner | Wholegrain toast |
| 1 | 2 | dinner | Salad |
| 1 | 2 | snack | Wholegrain toast |
| 1 | 2 | snack | Pumpkin seeds |
| 1 | 3 | dinner | Low-fat cottage cheese |
| 1 | 3 | dinner | Salad |
| 1 | 3 | snack | Ehrmann caffe latte |
| 1 | 4 | dinner | Egg whites |
| 1 | 4 | dinner | Whole egg |
| 1 | 4 | dinner | Wholegrain toast |
| 1 | 4 | dinner | Salad |
| 1 | 4 | snack | Gullon shortbread |
| 1 | 5 | dinner | Greek yogurt, plain |
| 1 | 5 | dinner | Salad |
| 1 | 5 | snack | Strawberry |
| 1 | 6 | dinner | Greek yogurt, plain |
| 1 | 6 | dinner | Wholegrain toast |
| 1 | 6 | dinner | Salad |
| 1 | 6 | snack | Digestive choco |
| 1 | 7 | dinner | Greek yogurt, plain |
| 1 | 7 | dinner | Oats |
| 1 | 7 | dinner | Blueberries |
| 1 | 7 | snack | Gullon shortbread |
| 2 | 8 | dinner | Greek yogurt, plain |
| 2 | 8 | dinner | Oats |
| 2 | 8 | dinner | Banana |
| 2 | 8 | snack | Strawberry |
| 2 | 9 | dinner | Low-fat cottage cheese |
| 2 | 9 | dinner | Wholegrain toast |
| 2 | 9 | dinner | Salad |
| 2 | 9 | snack | Pumpkin seeds |
| 2 | 10 | dinner | Egg whites |
| 2 | 10 | dinner | Whole egg |
| 2 | 10 | dinner | Wholegrain toast |
| 2 | 10 | dinner | Salad |
| 2 | 10 | snack | Pumpkin seeds |
| 2 | 11 | dinner | Egg whites |
| 2 | 11 | dinner | Whole egg |
| 2 | 11 | dinner | Wholegrain toast |
| 2 | 11 | dinner | Salad |
| 2 | 11 | snack | Digestive choco |
| 2 | 12 | dinner | Greek yogurt, plain |
| 2 | 12 | dinner | Salad |
| 2 | 12 | snack | Ehrmann caffe latte |
| 2 | 13 | dinner | Greek yogurt, plain |
| 2 | 13 | dinner | Salad |
| 2 | 13 | snack | Digestive choco |
| 2 | 14 | dinner | Greek yogurt, plain |
| 2 | 14 | dinner | Oats |
| 2 | 14 | dinner | Blueberries |
| 2 | 14 | snack | Gullon shortbread |
| 3 | 15 | dinner | Greek yogurt, plain |
| 3 | 15 | dinner | Oats |
| 3 | 15 | dinner | Banana |
| 3 | 15 | snack | Pumpkin seeds |
| 3 | 16 | dinner | Egg whites |
| 3 | 16 | dinner | Whole egg |
| 3 | 16 | dinner | Wholegrain toast |
| 3 | 16 | dinner | Salad |
| 3 | 16 | snack | Wholegrain toast |
| 3 | 16 | snack | Pumpkin seeds |
| 3 | 17 | dinner | Greek yogurt, plain |
| 3 | 17 | dinner | Salad |
| 3 | 17 | snack | Digestive choco |
| 3 | 18 | dinner | Egg whites |
| 3 | 18 | dinner | Whole egg |
| 3 | 18 | dinner | Wholegrain toast |
| 3 | 18 | dinner | Salad |
| 3 | 18 | snack | Digestive choco |
| 3 | 19 | dinner | Greek yogurt, plain |
| 3 | 19 | dinner | Wholegrain toast |
| 3 | 19 | dinner | Salad |
| 3 | 19 | snack | Pumpkin seeds |
| 3 | 20 | dinner | Greek yogurt, plain |
| 3 | 20 | dinner | Salad |
| 3 | 20 | snack | Digestive choco |
| 3 | 21 | dinner | Egg whites |
| 3 | 21 | dinner | Whole egg |
| 3 | 21 | dinner | Wholegrain toast |
| 3 | 21 | dinner | Salad |
| 3 | 21 | snack | Banana |
| 4 | 22 | dinner | Egg whites |
| 4 | 22 | dinner | Whole egg |
| 4 | 22 | dinner | Wholegrain toast |
| 4 | 22 | dinner | Salad |
| 4 | 22 | snack | Gullon shortbread |
| 4 | 23 | dinner | Low-fat cottage cheese |
| 4 | 23 | dinner | Salad |
| 4 | 23 | snack | Digestive choco |
| 4 | 24 | dinner | Greek yogurt, plain |
| 4 | 24 | dinner | Wholegrain toast |
| 4 | 24 | dinner | Salad |
| 4 | 24 | snack | Greek yogurt, plain |
| 4 | 25 | dinner | Greek yogurt, plain |
| 4 | 25 | dinner | Oats |
| 4 | 25 | dinner | Blueberries |
| 4 | 25 | snack | Pumpkin seeds |
| 4 | 26 | dinner | Low-fat cottage cheese |
| 4 | 26 | dinner | Salad |
| 4 | 26 | snack | Wholegrain toast |
| 4 | 26 | snack | Pumpkin seeds |
| 4 | 27 | dinner | Greek yogurt, plain |
| 4 | 27 | dinner | Wholegrain toast |
| 4 | 27 | dinner | Salad |
| 4 | 27 | snack | Gullon shortbread |
| 4 | 28 | dinner | Greek yogurt, plain |
| 4 | 28 | dinner | Oats |
| 4 | 28 | dinner | Banana |
| 4 | 28 | snack | Gullon shortbread |

### 0. Week grouping (decision needed? – applied as below)
- The PDF prints a WEEK header per page spread, so printed weeks hold 8/6/8/6 days (Day 8 *Saturday* is printed under WEEK 1; Day 22 *Saturday* under WEEK 3; Days 9-14 under WEEK 2 etc.). The requirement and the repeating Sat-Fri cycle say 7 days per week, so the app groups Days 1-7, 8-14, 15-21, 22-28. The PDF's own label is kept per day (`pdfWeekLabel`). Days whose printed label differs from the app week: 8, 22. Day content and order are unchanged.

### C. Iced coffee
- The PDF specifies calories only (25 g cilantro frappe 70 kcal + 170 ml skimmed milk ~60 kcal = ~130 kcal). Protein/carbs/fats/fiber are **unavailable (null)** – not estimated.
- PDF DAILY TOTAL excludes the coffee; "Updated calories" = DAILY TOTAL + 130. The app plans meals + coffee once (no double count) and keeps the PDF totals for reference.
- Footnote on every page: *"Estimated nutrition. Digestive Choco is approximate…"* – no "Digestive Choco" item appears in the plan; nothing imported for it.
