-- inserting loans
-- first testing the procedures

CALL LoanBook(1,1);
CALL LoanBook(26,1);
CALL LoanBook(94,1);
-- CALL LoanBook(99,1); -- user already borrowed 3 books in this library

-- CALL LoanBook(1,2); -- this book is already borrowed

CALL ExtendLoan(1);
-- CALL ExtendLoan(1); -- user already extended this loan
-- CALL ExtendLoan(5); -- loan with id 5 doesn't currently exist

CALL ReturnBook(1);
-- CALL ReturnBook(5); -- also loan with id 5 does not exist

INSERT INTO Loans (LoanID, BookCopyID, UserID, LoanDate, DueDate, PenaltyRate, Returned, Extended)
VALUES
  (4, 66, 3, '2023-01-01', '2023-01-21', 0, TRUE, FALSE),
  (5, 1500, 500, '2023-02-15', '2023-03-07', 0, TRUE, FALSE),
  (6, 3000, 750, '2023-03-10', '2023-04-09', 4, TRUE, TRUE),
  (7, 4500, 250, '2023-04-05', '2023-04-25', 0, TRUE, FALSE),
  (8, 6000, 1000, '2023-06-20', '2023-07-10', NULL, FALSE, FALSE);
INSERT INTO Loans (LoanID, BookCopyID, UserID, LoanDate, DueDate, PenaltyRate, Returned, Extended)
VALUES
  (9, 2847, 213, '2023-08-20', '2023-09-10', NULL, FALSE, FALSE);
INSERT INTO Loans (LoanID, BookCopyID, UserID, LoanDate, DueDate, PenaltyRate, Returned, Extended)
VALUES
  (10, 3500, 800, '2023-07-05', '2023-08-04', 0, true, false),
  (11, 5000, 150, '2023-08-20', '2023-10-19', 0, false, true),
  (12, 5500, 900, '2023-09-15', '2023-10-05', 0, true, true),
  (13, 1200, 700, '2023-10-10', '2023-11-09', 0, false, false),
  (14, 2500, 200, '2023-11-25', '2023-01-24', 0, true, false),
  (15, 4000, 600, '2023-12-05', '2023-02-04', 0, false, true),
  (16, 100, 950, '2023-01-01', '2023-01-21', 0, true, true),
  (17, 1800, 50, '2023-02-15', '2023-03-07', 0, false, false),
  (18, 2800, 920, '2023-03-10', '2023-04-09', 0, true, false);
INSERT INTO Loans (LoanID, BookCopyID, UserID, LoanDate, DueDate, PenaltyRate, Returned, Extended)
VALUES
  (19, 3300, 180, '2023-04-05', '2023-04-25', 5.20, true, FALSE),
  (20, 4800, 750, '2023-05-20', '2023-07-19', 0, false, false),
  (21, 5800, 550, '2023-06-12', '2023-07-02', 6, true, false),
  (22, 300, 800, '2023-07-05', '2023-08-04', null, false, true),
  (23, 1300, 250, '2023-08-20', '2023-10-19', 2.30, true, true),
  (24, 2800, 620, '2023-09-15', '2023-10-05', null, false, false),
  (25, 4300, 300, '2023-10-10', '2023-11-09', 0, true, false),
  (26, 5700, 900, '2023-11-25', '2024-01-24', null, false, true),
  (27, 1100, 700, '2023-12-05', '2024-02-04', 0, true, true),
  (28, 2600, 950, '2023-01-01', '2023-01-21', null, false, false),
  (29, 4700, 50, '2023-02-15', '2023-03-07', 5, true, false),
  (30, 5900, 920, '2023-03-10', '2023-04-09', null, false, true),
  (31, 700, 180, '2023-04-05', '2023-04-25', 0, true, true),
  (32, 900, 750, '2023-05-20', '2023-07-19', null, false, false),
  (33, 1200, 550, '2023-06-12', '2023-07-02', 3.50, true, false);
INSERT INTO Loans (LoanID, BookCopyID, UserID, LoanDate, DueDate, PenaltyRate, Returned, Extended)
VALUES
  (34, 546, 300, '2025-07-05', '2025-08-04', null, false, true),
  (35, 5356, 800, '2025-08-20', '2025-10-19', 0, true, true),
  (36, 45, 150, '2025-09-15', '2025-10-05', null, false, false),
  (37, 56, 920, '2025-10-10', '2025-11-09', 0, true, false),
  (38, 563, 700, '2025-11-25', '2026-01-24', null, false, true),
  (39, 654, 950, '2025-12-05', '2026-02-04', 0, true, true),
  (40, 280, 50, '2026-01-01', '2026-01-21', null, false, false),
  (41, 40, 620, '2026-02-15', '2026-03-07', 2, true, false),
  (42, 342, 300, '2026-03-10', '2026-04-09', null, false, true),
  (43, 435, 900, '2026-04-05', '2026-04-25', 5, true, true),
  (44, 200, 750, '2026-05-20', '2026-07-19', null, false, false),
  (45, 53, 550, '2026-06-12', '2026-07-02', 0, true, false),
  (46, 643, 800, '2026-07-05', '2026-08-04', null, false, true),
  (47, 612, 150, '2026-08-20', '2026-10-19', 4, true, true),
  (48, 4322, 920, '2026-09-15', '2026-10-05', null, false, false),
  (49, 100, 700, '2026-10-10', '2026-11-09', 0, true, false),
  (50, 1800, 950, '2026-11-25', '2027-01-24', null, false, true),
  (51, 3000, 50, '2026-12-05', '2027-02-04', 0, true, true),
  (52, 4500, 620, '2027-01-01', '2027-01-21', null, false, false);
