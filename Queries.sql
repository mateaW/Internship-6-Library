-- 1.
SELECT a.FirstName, a.LastName, a.Gender, s.Name, s.AverageWage
FROM Authors a
JOIN States s on s.StateID = a.StateID;

-- 2.
SELECT b.Name, b.PublicationDate, CONCAT(CONCAT(a.LastName, ' ', LEFT(a.FirstName, 1)), '.') AS MainAuthor
FROM Books b
JOIN BooksAuthors ba ON b.BookID = ba.BookID
JOIN Authors a ON a.AuthorID = ba.AuthorID
WHERE b.Type = 'Science Book' AND ba.AuthorType = 'Main Author';

-- 3.
SELECT
  b.Name,
  l.LoanDate
FROM
  Loans l
JOIN
  BookCopies bc ON bc.BookCopyID = l.BookCopyID
JOIN
  Books b ON b.BookID = bc.BookID
WHERE
  DATE_PART('year', l.LoanDate) = 2023 AND DATE_PART('month', l.LoanDate) = 12
ORDER BY
  l.LoanDate DESC;

-- 4.
SELECT l.Name, COUNT(bc.BookCopyID) AS NumberOfBooks
FROM Libraries l
JOIN BookCopies bc on bc.LibraryID = l.LibraryID
GROUP BY l.LibraryID, l.Name
ORDER BY NumberOfBooks DESC
LIMIT 3;

-- 5.
SELECT b.Name, COUNT(DISTINCT l.UserID) AS NumberOfReaders
FROM Loans l
JOIN
  BookCopies bc ON bc.BookCopyID = l.BookCopyID
JOIN
  Books b ON b.BookID = bc.BookID
GROUP BY b.Name
ORDER BY NumberOfReaders DESC;

-- 6.
SELECT DISTINCT u.FirstName, u.LastName
FROM Users u
JOIN Loans l ON l.UserID = u.UserID
WHERE l.Returned = FALSE;

-- 7.
SELECT DISTINCT a.FirstName, a.LastName
FROM Authors a 
JOIN BooksAuthors ba ON ba.AuthorID = a.AuthorID
JOIN Books b ON b.BookID = ba.BookID
WHERE b.PublicationDate BETWEEN '2019-01-01' AND '2020-12-31';

-- 8.
SELECT s.Name, COUNT(DISTINCT b.BookID) AS NumberOfArtBooks
FROM States s
JOIN Authors a on a.StateID = s.StateID
JOIN BooksAuthors ba ON ba.AuthorID = a.AuthorID
JOIN Books b ON b.BookID = ba.BookID
WHERE b.Type = 'Art Book'
GROUP BY s.Name
ORDER BY (SELECT COUNT(*) from Authors a WHERE a.YearOfDeath IS NULL) DESC;

-- 9.
SELECT
  a.FirstName,
  a.LastName,
  b.Type,
  COUNT(*) AS NumberOfBorrowings
FROM
  Authors a
JOIN
  BooksAuthors ba ON a.AuthorID = ba.AuthorID
JOIN
  Books b ON ba.BookID = b.BookID
JOIN
  BookCopies bc ON b.BookID = bc.BookID
JOIN
  Loans l ON bc.BookCopyID = l.BookCopyID
GROUP BY
  a.FirstName, a.LastName, b.Type
ORDER BY
  NumberOfBorrowings DESC;
  
-- 10.
SELECT a.FirstName, a.LastName, b.Name, MIN(b.PublicationDate) AS PublicationDate
FROM Authors a
JOIN BooksAuthors ba ON ba.AuthorID = a.AuthorID
JOIN Books b ON b.BookID = ba.BookID
GROUP BY a.FirstName, a.LastName, b.Name;

-- 11.
WITH RankedBooks AS (
  SELECT
    s.Name AS State,
    b.Name AS Book,
    b.PublicationDate,
    ROW_NUMBER() OVER (PARTITION BY s.StateID ORDER BY b.PublicationDate) AS BookRank
  FROM
    Books b
    JOIN BooksAuthors ba ON ba.BookID = b.BookID
    JOIN Authors a ON a.AuthorID = ba.AuthorID
    JOIN States s ON s.StateID = a.StateID
)
SELECT
  State,
  Book,
  PublicationDate
FROM
  RankedBooks
WHERE
  BookRank = 2;
  
-- 12.
SELECT
  b.Name,
  COUNT(*) AS ActiveBorrowings
FROM
  Books b
JOIN
  BookCopies bc ON bc.BookID = b.BookID
JOIN
  Loans l ON l.BookCopyID = bc.BookCopyID 
WHERE l.Returned = FALSE
GROUP BY
  b.Name
HAVING COUNT(*) >= 10;

-- 13.
SELECT
  State,
  AVG(AverageBorrowingsPerCopy) AS AverageBorrowingsPerCopy
FROM (
  SELECT
    s.Name AS State,
    bc.BookCopyID,
    COUNT(l.LoanID) / COUNT(DISTINCT bc.BookCopyID) AS AverageBorrowingsPerCopy
  FROM
    BookCopies bc
  JOIN
    Loans l ON l.BookCopyID = bc.BookCopyID
  JOIN
    Books b ON b.BookID = bc.BookID
  JOIN
    BooksAuthors ba ON ba.BookID = b.BookID
  JOIN
    Authors a ON a.AuthorID = ba.AuthorID
  JOIN
    States s ON s.StateID = a.StateID
  GROUP BY
    s.Name, bc.BookCopyID
) AS Subquery
GROUP BY
  State;

-- 14.
WITH AuthorCounts AS (
  SELECT
    a.FieldOfStudy,
    EXTRACT(DECADE FROM a.Birth) AS DecadeOfBirth,
    a.Gender,
    COUNT(DISTINCT a.AuthorID) AS AuthorCount
  FROM
    Authors a
    JOIN BooksAuthors ba ON a.AuthorID = ba.AuthorID
  GROUP BY
    a.FieldOfStudy,
    EXTRACT(DECADE FROM a.Birth),
    a.Gender
  HAVING
    COUNT(DISTINCT ba.BookID) > 5
)
SELECT
  FieldOfStudy,
  DecadeOfBirth,
  Gender,
  AuthorCount
FROM
  AuthorCounts
WHERE
  AuthorCount >= 10
ORDER BY
  DecadeOfBirth DESC;

-- 15.
SELECT
  Subquery.FirstName,
  Subquery.LastName,
  SUM(Subquery.ProfitPerBook) AS TotalProfit
FROM (
  SELECT
    a.AuthorID,
    a.FirstName,
    a.LastName,
    SQRT(COUNT(bc.BookID))/COUNT(DISTINCT ba.AuthorID) AS ProfitPerBook
  FROM
    Authors a
    JOIN BooksAuthors ba ON a.AuthorID = ba.AuthorID
    JOIN Books b ON ba.BookID = b.BookID
    JOIN BookCopies bc ON bc.BookID = b.BookID
  GROUP BY
    a.AuthorID,
    a.FirstName,
    a.LastName
) AS Subquery
GROUP BY
  Subquery.AuthorID,
  Subquery.FirstName,
  Subquery.LastName
ORDER BY
  TotalProfit DESC
LIMIT 10;