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