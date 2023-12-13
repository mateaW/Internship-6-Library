CREATE TABLE States (
	StateID SERIAL PRIMARY KEY,
	Name VARCHAR(100) NOT NULL,
	Population INT NOT NULL,
	AverageWage INT NOT NULL
);

CREATE TABLE Libraries (
	LibraryID SERIAL PRIMARY KEY,
	Name VARCHAR(100) NOT NULL,
	OpeningTime TIME,
	ClosingTime TIME
);

CREATE TABLE Librarians (
	LibrarianID SERIAL PRIMARY KEY,
	LibraryID INT REFERENCES Libraries(LibraryID),
	FirstName VARCHAR(100) NOT NULL,
	LastName VARCHAR(100) NOT NULL,
	Birth DATE NOT NULL,
	Gender VARCHAR(20) NOT NULL
);

CREATE TABLE Authors (
	AuthorID SERIAL PRIMARY KEY,
	FirstName VARCHAR(100) NOT NULL,
	LastName VARCHAR(100) NOT NULL,
	Birth DATE NOT NULL,
	Gender VARCHAR(20) NOT NULL,
	StateID INT REFERENCES States(StateID),
	YearOfDeath DATE,
	FieldOfStudy VARCHAR(50) NOT NULL
);

CREATE TABLE Books (
	BookID SERIAL PRIMARY KEY,
	Name VARCHAR(100) NOT NULL,
	Type VARCHAR(20) NOT NULL,
	PublicationDate DATE NOT NULL
);

CREATE TABLE BooksAuthors (
	BookID INT REFERENCES Books(BookID) ,
	AuthorID INT REFERENCES Authors(AuthorID),
	AuthorType VARCHAR(20) NOT NULL
);

CREATE TABLE BookCopies (
	BookCopiesID SERIAL PRIMARY KEY,
	BookCode VARCHAR(10) UNIQUE NOT NULL,
	BookID INT REFERENCES Books(BookID),
	LibraryID INT REFERENCES Libraries(LibraryID)
);

ALTER TABLE BookCopies
RENAME COLUMN BookCopiesID TO BookCopyID;

CREATE TABLE Users (
	UserID SERIAL PRIMARY KEY,
	FirstName VARCHAR(100) NOT NULL,
	LastName VARCHAR(100) NOT NULL,
	Birth DATE NOT NULL,
	Gender VARCHAR(20) NOT NULL
);

CREATE TABLE Loans (
	LoanID SERIAL PRIMARY KEY,
	BookCopyID INT REFERENCES BookCopies(BookCopyID),
	UserID INT REFERENCES Users(UserID),
	LoanDate DATE NOT NULL,
	DueDate DATE NOT NULL,
	PenaltyRate INT
);

ALTER TABLE Loans
ADD COLUMN Returned BOOLEAN NOT NULL;


-- constraints
ALTER TABLE Librarians
ADD CONSTRAINT CK_Gender
CHECK (Gender IN ('Male', 'Female', 'Unknown', 'Other'));

ALTER TABLE Authors
ADD CONSTRAINT CK_Gender
CHECK (Gender IN ('Male', 'Female', 'Unknown', 'Other'));

ALTER TABLE Users
ADD CONSTRAINT CK_Gender
CHECK (Gender IN ('Male', 'Female', 'Unknown', 'Other'));

ALTER TABLE Books
ADD CONSTRAINT CK_BookType
CHECK (Type IN ('Literary Book', 'Art Book', 'Science Book', 'Biography', 'Technical Book'));

ALTER TABLE BooksAuthors
ADD CONSTRAINT CK_AuthorType
CHECK (AuthorType IN ('Main Author', 'Co-Author'));


-- function that generates book codes
CREATE OR REPLACE FUNCTION generate_book_code()
RETURNS TRIGGER AS $$
BEGIN
  NEW.BookCode := SUBSTRING(
    MD5(RANDOM()::TEXT || clock_timestamp()::TEXT)::TEXT FROM 1 FOR 10
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- creating trigger
CREATE TRIGGER before_bookCopy_insert
BEFORE INSERT ON BookCopies
FOR EACH ROW
EXECUTE FUNCTION generate_book_code();

-- testing the function above if it will generate a random code to an added book copy
insert into States(Name,Population,AverageWage) values 
('Hrvatska', 4000000, 1100);
insert into Libraries(Name, OpeningTime, ClosingTime) values
('Knjižnica Marka Marulića', '08:00:00', '20:00:00');
insert into Books (Name, Type, PublicationDate) values
('Book1', 'Art Book', '02/01/2020');
insert into BookCopies (BookID, LibraryID) VALUES
(1,1);


-- procedure to borrow a book
-- it checks if the book is already borrowed by someone else 
-- it also checks if the user has already borrowed 3 books from that library
CREATE OR REPLACE PROCEDURE LoanBook(book_copy_id INT, user_id INT) AS
$$
DECLARE
    book_due_date DATE;
	book_loan_date DATE;
	current_loan_count INT;
	is_book_loaned BOOLEAN;
	library_id INT;
BEGIN
    -- checks if the book is available
    SELECT EXISTS (
        SELECT 1
        FROM Loans l
        INNER JOIN BookCopies bc ON l.BookCopiesID = bc.BookCopiesID
        WHERE bc.BookCopiesID = book_copy_id AND l.Returned IS FALSE) 
			INTO is_book_loaned;

    -- raise exception if the book is already borrowed
    IF is_book_loaned THEN
        RAISE EXCEPTION 'Book is already borrowed.';
	ELSE
		-- checks number of borrowed books in this library
        SELECT LibraryID
        INTO library_id
        FROM BookCopies
        WHERE BookCopyID = book_copy_id;

        SELECT COUNT(*)
        INTO current_loan_count
        FROM Loans l
        INNER JOIN BookCopies bc ON l.BookCopyID = bc.BookCopyID
        WHERE l.UserID = user_id AND bc.LibraryID = library_id;

		IF current_loan_count < 3 THEN
		-- it is assumed that the user borrowed the book today, 
		-- and the due date is set in 20 days
		book_due_date := CURRENT_DATE + INTERVAL '20 days';
		book_loan_date := CURRENT_DATE;

		-- insert into Loans table
		INSERT INTO Loans(BookCopyID, UserID, LoanDate, DueDate, Returned)
		VALUES (book_copy_id, user_id, book_loan_date, book_due_date, FALSE);
		RAISE NOTICE 'Book borrowed successfully. Due date: %', book_due_date;

		ELSE
			RAISE EXCEPTION 'User has already borrowed 3 books in this library.';
		END IF;
	END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error borrowing book: %', SQLERRM;
END;
$$
LANGUAGE plpgsql;


-- procedure to return a book, it calculates users penalty rate if he has one
CREATE OR REPLACE PROCEDURE ReturnBook(loan_id INT) AS
$$
DECLARE
    days_overdue INT;
    penalty_rate DECIMAL;
    is_literaryBook BOOLEAN;
BEGIN 
	-- check if there is delay
	SELECT 
		CASE 
			WHEN CURRENT_DATE > DueDate THEN 
				CURRENT_DATE - DueDate
			ELSE 
				0 
		END
	INTO days_overdue
    FROM Loans
    WHERE LoanID = loan_id;
	
	-- check if the book is literary book
	SELECT TRUE
    INTO is_literaryBook
    FROM Books b
    INNER JOIN BookCopies bc ON b.BookID = bc.BookID
    INNER JOIN Loans l ON bc.BookCopyID = l.BookCopyID
    WHERE l.LoanID = loan_id AND b.Type = 'Literary Book';
	
	-- calculating penalty rate
	SELECT 
        CASE 
			-- summer
            WHEN EXTRACT('month' FROM CURRENT_DATE) BETWEEN 6 AND 9 THEN 
                CASE 
                    WHEN EXTRACT('dow' FROM DueDate) BETWEEN 1 AND 5 THEN 
                        CASE 
							-- working days
                            WHEN is_literaryBook THEN 50  
                            ELSE 30  
                        END
					-- weekend
                    ELSE 20
                END
			-- not summer
            ELSE 
                CASE 
                    WHEN EXTRACT('dow' FROM DueDate) BETWEEN 1 AND 5 THEN 
                        CASE 
                            WHEN is_literaryBook THEN 50
                            ELSE 40  
                        END
                    ELSE 20
                END
        END
    INTO penalty_rate;
	
	-- insert into Loans table
	UPDATE Loans
    SET Returned = TRUE,
        PenaltyRate = penalty_rate
    WHERE LoanID = loan_id;

    RAISE NOTICE 'Book returned successfully. Penalty rate: %', penalty_rate;
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error returning book: %', SQLERRM;
END;
$$
LANGUAGE plpgsql;
	