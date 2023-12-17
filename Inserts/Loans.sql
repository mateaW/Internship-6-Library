-- inserting loans
-- first checking the procedures

CALL LoanBook(1,1);
CALL LoanBook(26,1);
CALL LoanBook(94,1);
-- CALL LoanBook(99,1); -- user already borrowed 3 books in this library

-- CALL LoanBook(1,2); -- this book is already borrowed

select * from Loans;

CALL ExtendLoan(1);
-- CALL ExtendLoan(1); -- user already extended this loan
-- CALL ExtendLoan(5); -- loan with id 5 doesn't currently exist

CALL ReturnBook(1);
-- CALL ReturnBook(5); -- also loan with id 5 does not exist