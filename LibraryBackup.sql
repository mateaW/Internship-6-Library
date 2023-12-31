PGDMP      &                {            DUMP_LIBRARY_DB    16.1    16.1 L               0    0    ENCODING    ENCODING        SET client_encoding = 'UTF8';
                      false                       0    0 
   STDSTRINGS 
   STDSTRINGS     (   SET standard_conforming_strings = 'on';
                      false                       0    0 
   SEARCHPATH 
   SEARCHPATH     8   SELECT pg_catalog.set_config('search_path', '', false);
                      false                       1262    65537    DUMP_LIBRARY_DB    DATABASE     �   CREATE DATABASE "DUMP_LIBRARY_DB" WITH TEMPLATE = template0 ENCODING = 'UTF8' LOCALE_PROVIDER = libc LOCALE = 'Croatian_Croatia.1250';
 !   DROP DATABASE "DUMP_LIBRARY_DB";
                postgres    false            �            1255    65648    extendloan(integer) 	   PROCEDURE     �  CREATE PROCEDURE public.extendloan(IN loan_id integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    current_due_date DATE;
    new_due_date DATE;
	is_extended BOOLEAN;
BEGIN
    -- check loan_id
    PERFORM 1 FROM Loans WHERE LoanID = loan_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Loan with ID % not found.', loan_id;
    END IF;
	
    SELECT DueDate, Extended INTO current_due_date, is_extended
    FROM Loans
    WHERE LoanID = loan_id;

	-- check if the book has already been extended
	IF NOT is_extended THEN
    	new_due_date := current_due_date + INTERVAL '60 days';
		is_extended := TRUE;
		-- insert updates into Loans table
		UPDATE Loans
		SET DueDate = new_due_date,
			Extended = is_extended
		WHERE LoanID = loan_id;
        RAISE NOTICE 'Loan extended successfully. New due date: %', new_due_date;
    ELSE
        RAISE EXCEPTION 'Cannot extend loan more than 1 time.';
    END IF;
	
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error extending loan: %', SQLERRM;
END;
$$;
 6   DROP PROCEDURE public.extendloan(IN loan_id integer);
       public          postgres    false            �            1255    65644    generate_book_code()    FUNCTION     �   CREATE FUNCTION public.generate_book_code() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.BookCode := SUBSTRING(
    MD5(RANDOM()::TEXT || clock_timestamp()::TEXT)::TEXT FROM 1 FOR 10
  );
  RETURN NEW;
END;
$$;
 +   DROP FUNCTION public.generate_book_code();
       public          postgres    false            �            1255    65646    loanbook(integer, integer) 	   PROCEDURE     �  CREATE PROCEDURE public.loanbook(IN book_copy_id integer, IN user_id integer)
    LANGUAGE plpgsql
    AS $$
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
        INNER JOIN BookCopies bc ON l.BookCopyID = bc.BookCopyID
        WHERE bc.BookCopyID = book_copy_id AND l.Returned IS FALSE) 
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
		INSERT INTO Loans(BookCopyID, UserID, LoanDate, DueDate, Returned, Extended)
		VALUES (book_copy_id, user_id, book_loan_date, book_due_date, FALSE, FALSE);
		RAISE NOTICE 'Book borrowed successfully. Due date: %', book_due_date;

		ELSE
			RAISE EXCEPTION 'User has already borrowed 3 books in this library.';
		END IF;
	END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error borrowing book: %', SQLERRM;
END;
$$;
 M   DROP PROCEDURE public.loanbook(IN book_copy_id integer, IN user_id integer);
       public          postgres    false            �            1255    65647    returnbook(integer) 	   PROCEDURE     �  CREATE PROCEDURE public.returnbook(IN loan_id integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
	due_date DATE;
    days_overdue INT;
    penalty_rate REAL := 0;
    is_literaryBook BOOLEAN;
	is_already_returned BOOLEAN;
BEGIN 
    -- check loan_id
    PERFORM 1 FROM Loans WHERE LoanID = loan_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Loan with ID % not found.', loan_id;
    END IF;
	
	-- check if the book has already been returned
    SELECT Returned INTO is_already_returned
    FROM Loans
    WHERE LoanID = loan_id;
    IF is_already_returned THEN
        RAISE EXCEPTION 'Book with Loan ID % has already been returned.', loan_id;
    END IF;
	
	SELECT DueDate INTO due_date
	FROM Loans
    WHERE LoanID = loan_id;
	
	-- check if there is delay
	SELECT 
		CASE 
			WHEN CURRENT_DATE > DueDate THEN 
				CURRENT_DATE - DueDate
			ELSE 
				0 
		END
	INTO days_overdue
    FROM Loans l
    WHERE LoanID = loan_id;
	
	-- check if the book is literary book
	SELECT TRUE
    INTO is_literaryBook
    FROM Books b
    INNER JOIN BookCopies bc ON b.BookID = bc.BookID
    INNER JOIN Loans l ON bc.BookCopyID = l.BookCopyID
    WHERE l.LoanID = loan_id AND b.Type = 'Literary Book';
	
	-- calculate penalty rate
	IF days_overdue > 0 THEN
		FOR i IN 1..days_overdue LOOP
			-- summer time
			IF EXTRACT(MONTH FROM due_date + i) BETWEEN 6 AND 9 THEN 
				IF EXTRACT(DOW FROM due_date + i) BETWEEN 1 AND 5 THEN 
					-- working days
					penalty_rate := penalty_rate + 0.3; 
				ELSE
					-- weekend
					penalty_rate := penalty_rate + 0.2; 
				END IF;
			-- not summer time
			ELSE 
				IF is_literaryBook THEN
					penalty_rate := penalty_rate + 0.5;
				ELSE
					-- working days
					IF EXTRACT(DOW FROM due_date + i) BETWEEN 1 AND 5 THEN
						penalty_rate := penalty_rate + 0.4; 
					ELSE
						-- weekend
						penalty_rate := penalty_rate + 0.2; 
					END IF;
				END IF;
			END IF;
		END LOOP;
	END IF;

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
$$;
 6   DROP PROCEDURE public.returnbook(IN loan_id integer);
       public          postgres    false            �            1259    65565    authors    TABLE     �  CREATE TABLE public.authors (
    authorid integer NOT NULL,
    firstname character varying(100) NOT NULL,
    lastname character varying(100) NOT NULL,
    birth date NOT NULL,
    gender character varying(20) NOT NULL,
    stateid integer,
    yearofdeath date,
    fieldofstudy character varying(50) NOT NULL,
    CONSTRAINT ck_gender CHECK (((gender)::text = ANY ((ARRAY['Male'::character varying, 'Female'::character varying, 'Unknown'::character varying, 'Other'::character varying])::text[])))
);
    DROP TABLE public.authors;
       public         heap    postgres    false            �            1259    65564    authors_authorid_seq    SEQUENCE     �   CREATE SEQUENCE public.authors_authorid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 +   DROP SEQUENCE public.authors_authorid_seq;
       public          postgres    false    222                       0    0    authors_authorid_seq    SEQUENCE OWNED BY     M   ALTER SEQUENCE public.authors_authorid_seq OWNED BY public.authors.authorid;
          public          postgres    false    221            �            1259    65597 
   bookcopies    TABLE     �   CREATE TABLE public.bookcopies (
    bookcopyid integer NOT NULL,
    bookcode character varying(10) NOT NULL,
    bookid integer,
    libraryid integer
);
    DROP TABLE public.bookcopies;
       public         heap    postgres    false            �            1259    65596    bookcopies_bookcopiesid_seq    SEQUENCE     �   CREATE SEQUENCE public.bookcopies_bookcopiesid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 2   DROP SEQUENCE public.bookcopies_bookcopiesid_seq;
       public          postgres    false    227                       0    0    bookcopies_bookcopiesid_seq    SEQUENCE OWNED BY     Y   ALTER SEQUENCE public.bookcopies_bookcopiesid_seq OWNED BY public.bookcopies.bookcopyid;
          public          postgres    false    226            �            1259    65577    books    TABLE     �  CREATE TABLE public.books (
    bookid integer NOT NULL,
    name character varying(100) NOT NULL,
    type character varying(20) NOT NULL,
    publicationdate date NOT NULL,
    CONSTRAINT ck_booktype CHECK (((type)::text = ANY ((ARRAY['Literary Book'::character varying, 'Art Book'::character varying, 'Science Book'::character varying, 'Biography'::character varying, 'Technical Book'::character varying])::text[])))
);
    DROP TABLE public.books;
       public         heap    postgres    false            �            1259    65576    books_bookid_seq    SEQUENCE     �   CREATE SEQUENCE public.books_bookid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 '   DROP SEQUENCE public.books_bookid_seq;
       public          postgres    false    224                       0    0    books_bookid_seq    SEQUENCE OWNED BY     E   ALTER SEQUENCE public.books_bookid_seq OWNED BY public.books.bookid;
          public          postgres    false    223            �            1259    65583    booksauthors    TABLE       CREATE TABLE public.booksauthors (
    bookid integer,
    authorid integer,
    authortype character varying(20) NOT NULL,
    CONSTRAINT ck_authortype CHECK (((authortype)::text = ANY ((ARRAY['Main Author'::character varying, 'Co-Author'::character varying])::text[])))
);
     DROP TABLE public.booksauthors;
       public         heap    postgres    false            �            1259    65553 
   librarians    TABLE     �  CREATE TABLE public.librarians (
    librarianid integer NOT NULL,
    libraryid integer,
    firstname character varying(100) NOT NULL,
    lastname character varying(100) NOT NULL,
    birth date NOT NULL,
    gender character varying(20) NOT NULL,
    CONSTRAINT ck_gender CHECK (((gender)::text = ANY ((ARRAY['Male'::character varying, 'Female'::character varying, 'Unknown'::character varying, 'Other'::character varying])::text[])))
);
    DROP TABLE public.librarians;
       public         heap    postgres    false            �            1259    65552    librarians_librarianid_seq    SEQUENCE     �   CREATE SEQUENCE public.librarians_librarianid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 1   DROP SEQUENCE public.librarians_librarianid_seq;
       public          postgres    false    220                       0    0    librarians_librarianid_seq    SEQUENCE OWNED BY     Y   ALTER SEQUENCE public.librarians_librarianid_seq OWNED BY public.librarians.librarianid;
          public          postgres    false    219            �            1259    65546 	   libraries    TABLE     �   CREATE TABLE public.libraries (
    libraryid integer NOT NULL,
    name character varying(100) NOT NULL,
    openingtime time without time zone,
    closingtime time without time zone
);
    DROP TABLE public.libraries;
       public         heap    postgres    false            �            1259    65545    libraries_libraryid_seq    SEQUENCE     �   CREATE SEQUENCE public.libraries_libraryid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 .   DROP SEQUENCE public.libraries_libraryid_seq;
       public          postgres    false    218                       0    0    libraries_libraryid_seq    SEQUENCE OWNED BY     S   ALTER SEQUENCE public.libraries_libraryid_seq OWNED BY public.libraries.libraryid;
          public          postgres    false    217            �            1259    65623    loans    TABLE     �   CREATE TABLE public.loans (
    loanid integer NOT NULL,
    bookcopyid integer,
    userid integer,
    loandate date NOT NULL,
    duedate date NOT NULL,
    penaltyrate integer,
    returned boolean NOT NULL,
    extended boolean NOT NULL
);
    DROP TABLE public.loans;
       public         heap    postgres    false            �            1259    65622    loans_loanid_seq    SEQUENCE     �   CREATE SEQUENCE public.loans_loanid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 '   DROP SEQUENCE public.loans_loanid_seq;
       public          postgres    false    231                       0    0    loans_loanid_seq    SEQUENCE OWNED BY     E   ALTER SEQUENCE public.loans_loanid_seq OWNED BY public.loans.loanid;
          public          postgres    false    230            �            1259    65539    states    TABLE     �   CREATE TABLE public.states (
    stateid integer NOT NULL,
    name character varying(100) NOT NULL,
    population integer NOT NULL,
    averagewage integer NOT NULL
);
    DROP TABLE public.states;
       public         heap    postgres    false            �            1259    65538    states_stateid_seq    SEQUENCE     �   CREATE SEQUENCE public.states_stateid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 )   DROP SEQUENCE public.states_stateid_seq;
       public          postgres    false    216                       0    0    states_stateid_seq    SEQUENCE OWNED BY     I   ALTER SEQUENCE public.states_stateid_seq OWNED BY public.states.stateid;
          public          postgres    false    215            �            1259    65616    users    TABLE     �  CREATE TABLE public.users (
    userid integer NOT NULL,
    firstname character varying(100) NOT NULL,
    lastname character varying(100) NOT NULL,
    birth date NOT NULL,
    gender character varying(20) NOT NULL,
    CONSTRAINT ck_gender CHECK (((gender)::text = ANY ((ARRAY['Male'::character varying, 'Female'::character varying, 'Unknown'::character varying, 'Other'::character varying])::text[])))
);
    DROP TABLE public.users;
       public         heap    postgres    false            �            1259    65615    users_userid_seq    SEQUENCE     �   CREATE SEQUENCE public.users_userid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 '   DROP SEQUENCE public.users_userid_seq;
       public          postgres    false    229                       0    0    users_userid_seq    SEQUENCE OWNED BY     E   ALTER SEQUENCE public.users_userid_seq OWNED BY public.users.userid;
          public          postgres    false    228            H           2604    65568    authors authorid    DEFAULT     t   ALTER TABLE ONLY public.authors ALTER COLUMN authorid SET DEFAULT nextval('public.authors_authorid_seq'::regclass);
 ?   ALTER TABLE public.authors ALTER COLUMN authorid DROP DEFAULT;
       public          postgres    false    221    222    222            J           2604    65600    bookcopies bookcopyid    DEFAULT     �   ALTER TABLE ONLY public.bookcopies ALTER COLUMN bookcopyid SET DEFAULT nextval('public.bookcopies_bookcopiesid_seq'::regclass);
 D   ALTER TABLE public.bookcopies ALTER COLUMN bookcopyid DROP DEFAULT;
       public          postgres    false    227    226    227            I           2604    65580    books bookid    DEFAULT     l   ALTER TABLE ONLY public.books ALTER COLUMN bookid SET DEFAULT nextval('public.books_bookid_seq'::regclass);
 ;   ALTER TABLE public.books ALTER COLUMN bookid DROP DEFAULT;
       public          postgres    false    224    223    224            G           2604    65556    librarians librarianid    DEFAULT     �   ALTER TABLE ONLY public.librarians ALTER COLUMN librarianid SET DEFAULT nextval('public.librarians_librarianid_seq'::regclass);
 E   ALTER TABLE public.librarians ALTER COLUMN librarianid DROP DEFAULT;
       public          postgres    false    220    219    220            F           2604    65549    libraries libraryid    DEFAULT     z   ALTER TABLE ONLY public.libraries ALTER COLUMN libraryid SET DEFAULT nextval('public.libraries_libraryid_seq'::regclass);
 B   ALTER TABLE public.libraries ALTER COLUMN libraryid DROP DEFAULT;
       public          postgres    false    218    217    218            L           2604    65626    loans loanid    DEFAULT     l   ALTER TABLE ONLY public.loans ALTER COLUMN loanid SET DEFAULT nextval('public.loans_loanid_seq'::regclass);
 ;   ALTER TABLE public.loans ALTER COLUMN loanid DROP DEFAULT;
       public          postgres    false    231    230    231            E           2604    65542    states stateid    DEFAULT     p   ALTER TABLE ONLY public.states ALTER COLUMN stateid SET DEFAULT nextval('public.states_stateid_seq'::regclass);
 =   ALTER TABLE public.states ALTER COLUMN stateid DROP DEFAULT;
       public          postgres    false    216    215    216            K           2604    65619    users userid    DEFAULT     l   ALTER TABLE ONLY public.users ALTER COLUMN userid SET DEFAULT nextval('public.users_userid_seq'::regclass);
 ;   ALTER TABLE public.users ALTER COLUMN userid DROP DEFAULT;
       public          postgres    false    228    229    229                      0    65565    authors 
   TABLE DATA           s   COPY public.authors (authorid, firstname, lastname, birth, gender, stateid, yearofdeath, fieldofstudy) FROM stdin;
    public          postgres    false    222   ;o                 0    65597 
   bookcopies 
   TABLE DATA           M   COPY public.bookcopies (bookcopyid, bookcode, bookid, libraryid) FROM stdin;
    public          postgres    false    227   n�                 0    65577    books 
   TABLE DATA           D   COPY public.books (bookid, name, type, publicationdate) FROM stdin;
    public          postgres    false    224   ��                0    65583    booksauthors 
   TABLE DATA           D   COPY public.booksauthors (bookid, authorid, authortype) FROM stdin;
    public          postgres    false    225    �                0    65553 
   librarians 
   TABLE DATA           `   COPY public.librarians (librarianid, libraryid, firstname, lastname, birth, gender) FROM stdin;
    public          postgres    false    220   &�      �          0    65546 	   libraries 
   TABLE DATA           N   COPY public.libraries (libraryid, name, openingtime, closingtime) FROM stdin;
    public          postgres    false    218   ��                0    65623    loans 
   TABLE DATA           o   COPY public.loans (loanid, bookcopyid, userid, loandate, duedate, penaltyrate, returned, extended) FROM stdin;
    public          postgres    false    231   n�      �          0    65539    states 
   TABLE DATA           H   COPY public.states (stateid, name, population, averagewage) FROM stdin;
    public          postgres    false    216   ��      
          0    65616    users 
   TABLE DATA           K   COPY public.users (userid, firstname, lastname, birth, gender) FROM stdin;
    public          postgres    false    229    �                 0    0    authors_authorid_seq    SEQUENCE SET     C   SELECT pg_catalog.setval('public.authors_authorid_seq', 1, false);
          public          postgres    false    221                       0    0    bookcopies_bookcopiesid_seq    SEQUENCE SET     J   SELECT pg_catalog.setval('public.bookcopies_bookcopiesid_seq', 1, false);
          public          postgres    false    226                       0    0    books_bookid_seq    SEQUENCE SET     ?   SELECT pg_catalog.setval('public.books_bookid_seq', 1, false);
          public          postgres    false    223                       0    0    librarians_librarianid_seq    SEQUENCE SET     I   SELECT pg_catalog.setval('public.librarians_librarianid_seq', 1, false);
          public          postgres    false    219                       0    0    libraries_libraryid_seq    SEQUENCE SET     F   SELECT pg_catalog.setval('public.libraries_libraryid_seq', 1, false);
          public          postgres    false    217                        0    0    loans_loanid_seq    SEQUENCE SET     >   SELECT pg_catalog.setval('public.loans_loanid_seq', 3, true);
          public          postgres    false    230            !           0    0    states_stateid_seq    SEQUENCE SET     A   SELECT pg_catalog.setval('public.states_stateid_seq', 1, false);
          public          postgres    false    215            "           0    0    users_userid_seq    SEQUENCE SET     ?   SELECT pg_catalog.setval('public.users_userid_seq', 1, false);
          public          postgres    false    228            Y           2606    65570    authors authors_pkey 
   CONSTRAINT     X   ALTER TABLE ONLY public.authors
    ADD CONSTRAINT authors_pkey PRIMARY KEY (authorid);
 >   ALTER TABLE ONLY public.authors DROP CONSTRAINT authors_pkey;
       public            postgres    false    222            ]           2606    65604 "   bookcopies bookcopies_bookcode_key 
   CONSTRAINT     a   ALTER TABLE ONLY public.bookcopies
    ADD CONSTRAINT bookcopies_bookcode_key UNIQUE (bookcode);
 L   ALTER TABLE ONLY public.bookcopies DROP CONSTRAINT bookcopies_bookcode_key;
       public            postgres    false    227            _           2606    65602    bookcopies bookcopies_pkey 
   CONSTRAINT     `   ALTER TABLE ONLY public.bookcopies
    ADD CONSTRAINT bookcopies_pkey PRIMARY KEY (bookcopyid);
 D   ALTER TABLE ONLY public.bookcopies DROP CONSTRAINT bookcopies_pkey;
       public            postgres    false    227            [           2606    65582    books books_pkey 
   CONSTRAINT     R   ALTER TABLE ONLY public.books
    ADD CONSTRAINT books_pkey PRIMARY KEY (bookid);
 :   ALTER TABLE ONLY public.books DROP CONSTRAINT books_pkey;
       public            postgres    false    224            W           2606    65558    librarians librarians_pkey 
   CONSTRAINT     a   ALTER TABLE ONLY public.librarians
    ADD CONSTRAINT librarians_pkey PRIMARY KEY (librarianid);
 D   ALTER TABLE ONLY public.librarians DROP CONSTRAINT librarians_pkey;
       public            postgres    false    220            U           2606    65551    libraries libraries_pkey 
   CONSTRAINT     ]   ALTER TABLE ONLY public.libraries
    ADD CONSTRAINT libraries_pkey PRIMARY KEY (libraryid);
 B   ALTER TABLE ONLY public.libraries DROP CONSTRAINT libraries_pkey;
       public            postgres    false    218            c           2606    65628    loans loans_pkey 
   CONSTRAINT     R   ALTER TABLE ONLY public.loans
    ADD CONSTRAINT loans_pkey PRIMARY KEY (loanid);
 :   ALTER TABLE ONLY public.loans DROP CONSTRAINT loans_pkey;
       public            postgres    false    231            S           2606    65544    states states_pkey 
   CONSTRAINT     U   ALTER TABLE ONLY public.states
    ADD CONSTRAINT states_pkey PRIMARY KEY (stateid);
 <   ALTER TABLE ONLY public.states DROP CONSTRAINT states_pkey;
       public            postgres    false    216            a           2606    65621    users users_pkey 
   CONSTRAINT     R   ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (userid);
 :   ALTER TABLE ONLY public.users DROP CONSTRAINT users_pkey;
       public            postgres    false    229            l           2620    65645 !   bookcopies before_bookcopy_insert    TRIGGER     �   CREATE TRIGGER before_bookcopy_insert BEFORE INSERT ON public.bookcopies FOR EACH ROW EXECUTE FUNCTION public.generate_book_code();
 :   DROP TRIGGER before_bookcopy_insert ON public.bookcopies;
       public          postgres    false    232    227            e           2606    65571    authors authors_stateid_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.authors
    ADD CONSTRAINT authors_stateid_fkey FOREIGN KEY (stateid) REFERENCES public.states(stateid);
 F   ALTER TABLE ONLY public.authors DROP CONSTRAINT authors_stateid_fkey;
       public          postgres    false    216    4691    222            h           2606    65605 !   bookcopies bookcopies_bookid_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.bookcopies
    ADD CONSTRAINT bookcopies_bookid_fkey FOREIGN KEY (bookid) REFERENCES public.books(bookid);
 K   ALTER TABLE ONLY public.bookcopies DROP CONSTRAINT bookcopies_bookid_fkey;
       public          postgres    false    227    4699    224            i           2606    65610 $   bookcopies bookcopies_libraryid_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.bookcopies
    ADD CONSTRAINT bookcopies_libraryid_fkey FOREIGN KEY (libraryid) REFERENCES public.libraries(libraryid);
 N   ALTER TABLE ONLY public.bookcopies DROP CONSTRAINT bookcopies_libraryid_fkey;
       public          postgres    false    218    4693    227            f           2606    65591 '   booksauthors booksauthors_authorid_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.booksauthors
    ADD CONSTRAINT booksauthors_authorid_fkey FOREIGN KEY (authorid) REFERENCES public.authors(authorid);
 Q   ALTER TABLE ONLY public.booksauthors DROP CONSTRAINT booksauthors_authorid_fkey;
       public          postgres    false    222    225    4697            g           2606    65586 %   booksauthors booksauthors_bookid_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.booksauthors
    ADD CONSTRAINT booksauthors_bookid_fkey FOREIGN KEY (bookid) REFERENCES public.books(bookid);
 O   ALTER TABLE ONLY public.booksauthors DROP CONSTRAINT booksauthors_bookid_fkey;
       public          postgres    false    224    225    4699            d           2606    65559 $   librarians librarians_libraryid_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.librarians
    ADD CONSTRAINT librarians_libraryid_fkey FOREIGN KEY (libraryid) REFERENCES public.libraries(libraryid);
 N   ALTER TABLE ONLY public.librarians DROP CONSTRAINT librarians_libraryid_fkey;
       public          postgres    false    4693    220    218            j           2606    65629    loans loans_bookcopyid_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.loans
    ADD CONSTRAINT loans_bookcopyid_fkey FOREIGN KEY (bookcopyid) REFERENCES public.bookcopies(bookcopyid);
 E   ALTER TABLE ONLY public.loans DROP CONSTRAINT loans_bookcopyid_fkey;
       public          postgres    false    231    4703    227            k           2606    65634    loans loans_userid_fkey    FK CONSTRAINT     y   ALTER TABLE ONLY public.loans
    ADD CONSTRAINT loans_userid_fkey FOREIGN KEY (userid) REFERENCES public.users(userid);
 A   ALTER TABLE ONLY public.loans DROP CONSTRAINT loans_userid_fkey;
       public          postgres    false    4705    231    229                  x�u[K{�6�]�������{�G��I�������7H�%�(��(���*�$H%��mA �q�*8�f��J<��=�Z�UZ\E镌�J��I���U_E��fNڪSo�')��z}��y�����UD_����?��D|>�=�eO���',��/.�E�XWqt%�pu*nl�:�����h˨��2|֝V��Q��pm&�=��S�^w���o�����Q\��,\��_�ŉ��m{��Jy�s�q��K���it�}*�w�֦Q8�:�km�&�l9��s�F[t�k{�T�ϵ�7���i��i�*��>�W�i�����4�O�n�� {��yII_WnMJ��'d��0��S����]���Y�Er�5���j�۟��O]K�����JG3,Ix��ċ��A�^E9Ő_����Dsj�݃n��}�
&�B�e�'6��g�S��n�m�6�E9nW�E#�(�d�E&�j`s��ݜZ:j�qp��[���߻3ټݝ?�1?�";��[�l�IU�y���YD^���}�CH*q�S�y�����2L6-+�o�V�(�b�#Ȩi`�4��u9�#�n60�DYx�$�k�i]�H��"�����#$ް@p����V��%'S�q?��+�� b�NӘW����"���.��}P�Y��m���"U���ݦŁm�i�u�\�!�ɤ�En�=�ve� ��]K�y8C2?m�؍�[x�ih��8��L�Ğ���i3�E5䓶�ĭ8̲�D�򜹸��be�ޫ#AgNk��
�b�S�Bp��+�AĴ'BN����OΙ�%%��+�������t�¥E�'�D5�^S6�[�s����5D��G⺷�Ub�O{�&w�| E�e��W�w=�"U �ҵ�?�Z��m��Wz�r�L(3����H���}�8��a��w�D�i�_J�pD����f�9�F�\��|�L�f�$��[�wC],��E!�nA=��%n
4��[fɐ���0g�EaR��^���i�K<P\�eԞ�^%���ZS��o}<z�b?]�'ެ�PoP�,��ޞ�m_���nW\N� !pۈcu�si$~�k�k �j���-��0� 4��3 F��Nl�9��摲~X<�o����B�Q���FX�z�P�}9K�֎gN8�,Bh�� ,7Zo#ׁM&�;�1e_�R�����>:���ń���V�A��3�j�0:鳣E��7pj�J����6������brFx1Е���ۛ�:t�
Vq��P��B����yPum�}�n��c̪HΝ�r�G3�UDBv�i�r�U��ʻ@F�B!�� ��{k��5֡�nk}�ɘSFW�9����w>.9*z%so,dx<�4C�(�ط*9��p�t�,��X�N9�Ҙ=;���`8��Bsf)���5绾�j�I�cFEg@m�(s�-�#/ʪ�x9ۏ��2Q:�4ձ02�"���U����(�7,��3+�Z�l+~"�<qf:g��{J�]���y+�Z2*
�eP��l�P8N}緋FOę�TE�/��P�
�Խk��+�tI���'f���y�$O7�aCx|���hs�*M� �ؒ�Wp��߶���ʜ�x�$��z���|�Xם~�'f��sM�N�E)��T<B�h�Sm�ca��̖:�s9
}�g�%&�����x�I�F�	��I��5��w@����4s�=�,�Q� ��[���:�� �9iA��%�3(�f���<�N��l/\Pᢒ���Ө�h~���
�E�z՛���[�a��h��q�!>S�"~R�iw��m�=�J�|�N�r�{���S��5,�s�&*(���|�D��	�M�����o��ē3���8�D�m�́*ν�mK'J���g(J
���*�z�Rap�p�dI�����\[�G塃��[U�����pe!��(XH���Q'a�*&qt�,Z̖(tk�T��{��ʡ3!� uK[T�W�������N�|�b�6)#��5��B-n<2A�&̊ROǃ=K0�Ik�a��O3�R��R�]�g N,8	��ݖ��}��}���c��[�΁�i����R���w��If/�D��p�M�J�s�O%C���h���j��2��`|{d w
��KMƋq�!�K��A�@mC�2�z9	e�����Y�(K��7-���]�X+�|y�
�^�@���S�G�L��k�`�
���heBJ��}1d��r�r�b#��5"�%���C��Ҍǜ�s���Uo:����z�p�v�R#a��ST	�@QYy���k��mw�T'��0���%W��K��T��Je��l�m&c���J��{���UC_^2����FE���y���~AI#�6��Uyِ�S�a����g���f5Y�\�_y��E
nc�ú���#T,��mJ�E��(L�'�C�a^I�9��?`�n�]�[�q����ꯛo$��`8�~n�Z�UQ�HL�|H���{2eO&�-������i���7-�V�?�f�3��u,�5��]ӷ��t�������L���w�V>)�v.@��o$�a���9�e�V�~ζ�Z��+FJ	�����`A�;�|��bn����6Ǟ�MZx�+wɎ��]��o�?U�R��kn��,S���b�Rq�/��Q����m�PQ�z�v)�l
�֞���_������'� �s ���|u�T�� |}���9�{:�s�;��<b|��Z�AJ���`/��XS���F���x1��Y�۶a�:s
�A�%�0�֮u'�A�ՀV���8���A���*4-f�{�z�a��ӆ~�iY�F�o�����Y��U���m[��2��r��S��*�YұEj2}�����q1��P
�`�O[.$��5�W�!��ԗ ��MA[z��(���L^��9q�8��%v́��*a���|���l���`���V�$�#�f��kB��O���e���^LĽ���$�)$,g��~�͙�'�=���-7�uK#	�;�A��S�_y��t`	 S�EjV��2�.���4̾��G;�:��^q���")���`�:��/�ۨ��m�J�>�g]�ٴ����h�^���o�5�B�u�*aՓ�K`Us�sq�NvW���RU�t�'@E�}z�L��N�C�X\4���&�x����2O��3G�J�K��T�e�g.�e�g�+U�*$�&k�0�k���W���Li�0c��-�;��*^9R�t�1����Ge�^�&N�\S��kw��cB ��,Ƞ��K�-��^iDf����q=���Kf�ԁ���1|y��)>���)�%�/��P�T4Dd4�ػ�.���2@D��I���"�h(8�R-�T�����NĻ��sw�'�i\�)���l5�����̖SD4�3r�>�j1q<�eq��b1��w�3Tnj�=;�Iy3Ɖ,��t�`~ɂ��4��ͻ�8�Q��n4G�:y�<���?yq����BNs���xۿ����5�����\+�(��P?��|{㊟�j�ʷ���*j��G�0�84<�MDOwcܖ���0���l�F����V2��d�f���7�*���Uq��o8�w�l��Y�P��_��ϔ����I��K�����LL[�}f�E���Y"S��:C�X��|k?��5^�fc��͚�˧qV���¡��J��E�#���ktޘθ��Iy��R�.h�UN��g�v�&A�'r���<���X�3(�9\P'�Q%}3$�<!4��x��q�kNSK����9[,�O��rc�1�ѧJ8��դ��eu��֭�>�'rS�8�
j�Q�m;��K�Վ�8���L�)/_x��<��� y����u!gJ��8Y(J~&'�ymM����QKk y!�O��:��ڶ)2	�r�}��R�ˮ�`����bG����e�P#sRߐv|4?zw%rj[�J?.",���Cq�,D��H\��!pT-� ��taƩs��
WH��hsR��*0�<^�#�1����蕎S�����X%Wn�4�"�;���=jY�y��!��e����JuC�c0   �5S��솥Z��i��hG��+j̧��[���f�*"P0�N;H#G���b�� ?MXUDKS�����*� �lY�#����5�bnS�3G��)#���C���^v�!�,�q���gsl<�q-�|��yq� �KI쀶��B`���z6J��j��P�g���E�ac��L��ૅI �V��o�k���U�G�<A�eE���X�yԏ�x��nQ�9#��_\�T��-�)������ 2��3*�����l���qg�R���E���xl�F|�:��8��C�y�2.�sퟺ�M�[�w�F���Q8ߜ �����H��<j�c�|GU�4G�9�gR�Z�o.�%����A�ГC띑�0���u���)\H�Z��a���ah���XK�j|�6f��$�O� �gkP$xrӞY������B�f-�C!����̫{U�r*˅Mg�Z�9���`0��w՜<)��0�)�]�
q��6M��|�7��P]^�"5u���N�𶵘��L��1|MEpș��+ ��tо�\4]�w`�xj^mk��{����̦���1�\l,��I��@�,��l� w�C�:c����AT
d�Q2�]�'�iՋaV��a�LO3��������#[����}>w*o��o�X����Nh�n��ڟ��%�೧��%�Mj�$���Y5u�����<�~�ۏ�~���i��IfS�4un���V��$�ۆ��yo� ��H�.�px���&���Zb[2���v�X���ȇ�"��<�MȆ�Lˤ����f����*8k�rxI�7o%����Z?�f=�{���K<��%t��e�-Cu�8^F?¤�=�(ϣ��� ǝ�.�z"4!��/���A���)�����Zo��{ ��g����}*f��H��F�����E�S�Ե��7jˣ��/<����4s�'_�7���7fՃt7�y6{��8�=ȷYK20����+s��3Ɍщ��kND�oۚ^��7	�˝�l��J���:G�;7P)<tˣ�PPߥi�a�QK)��E1�����͙'g����ɓ�WZ��ӝJ:�i��_B����i��!�.��D ���v��\��x��^��w{[�?}�Ɓ��eS*��U��K�SR���ԛG�,X}�'q�+R�i���q�z��a�0��!���þ!��鼉�O^\�ޮHX��Ll��@�����鿄Jh�E��;ʦo����xq]�l�E%�����p�=3��d5��T�#�)`��v��;:2�p�zIB��D�������LrpY+n� 
�����Å�!5~bxT��|�ڸ*0���Q_��Pֽ���6���"J~3'��	\��&U����#�o{�~�쭮�f1_h�1�X"�l�.5b���_L�ٻ^S4�EJ���5��֙������T��8���(�a��zJ`�g:8S��ݟ1�V��
��7�r9���ͥ��jT���:��ȶ�.J�mxwSi�C]uO�7©���q}bE�ү�^NS�ʰ#���??}���.m�R            x�D�W�,��D��V-���%Ю#_sx����pa.ῳz��п����)�t�K�B����%z���_��]�K_v'��(�_���e�TC���YS�?&����
��_�7����~����_�Bru�]\�Rt_����0[]�N��>������qn�ڿ���5���Q[,;k���?>��O�ؾ���?�F�qޕ?߳����쥇��]�4c���u���'����7�m{f��[5럯ߌ�V�A���߾���L���)��_9��oJ_�ڟ����7��t�Z^����2��U��6�__͡�9z�_q�~��u���n>NQ�����=�\�F����ڋ;�-S�Q����u+�.�����~��.�5�L��B�NO���/7��t��I�t7��ǔ���u���u���~�_��8ק!��b���c���R�=�?͐���k���:���><�_��M��Ա���!�t�L�)EY��2VӔQ��~cޭӚKgW�+�A^N�]M�M�*��%_7��.����Dfk,m��A�Й%�r��ŰD�Q�m����m�\QJ�;Iӵ©���Bß�\����*f�V���ޜ�h�Q��K�ӵ�u|	\`��D��6Qr�~|Q��R�\�SDZG�����RW�U����y�Xz���&-\c������>,�����τ3������z����n���O����:��.F��ϵ�{��O�qk.���\(qF���_3�Hn)9�!���ĄH��p��n"#*���w�͢�@_ֆ�f�{�݈�h��o�9׮�a�YH%|��vJ���O��"�I����
Dh�P�0���9�~$Cܟ�������ڠ�C��,J�x۔(^�=A�$-��b��g�� ����n�����V.��qE��Q���w�;��^�r�Or��z�M#�+������Ĺ��ͥU6�&����MQ�%V���_g��2#�*�Vc��O�E&����ʝ!���E�uӷ���O��F:�;��������"y�x��\�D��$�t��-I����Ib�зԏH�AE-J��n�Nd%J����=k�w�~#u!rӴ���9��H2NI|��b�\��4�uČ�i;�n+Oi�������@%kj��h���Z�n�|N�A�#��Z��\�ݏ�J������]�d�v�v#v���=�zT��=�᧗�
R@�M�?1[���Y���n��f����q��F��6��v�gl���c���]C�����g�+�[@�H�9��^5����ː���J��n�ػ��$��F��7AD��̦�R��נ�'�sD��|v�މs�_	�/���u�;b��F�OI@q�7����`F�3k��n����`���T(){Q��%+��t��I���MD)e�����U*1��B�.ɲz2��PH�:1`H7lI]g`ќH��3��at/������-��2A����t�I��O�w������V 6�����iP�*�
�J�U���J�dq��M�}<�A�����J� d�%�D�,����Z%}��ZÇ�&���t�ޒBٰ]��;�ݳE�G#���|m����1ɿ�>ȵw�TD��ը�1��܍2&����b�NI��݀X�D���X,�J�d��"`S��j���c�%��jѐıf�-�,��<��%\���$â�A�7'-�S�7�|�^�$�T����KU;-' e�[�=I��XV!�9�R!��4���/� �$�e-��3�g�~������R[</�Ĩ�Q)�$m�]�f�/�����q�����<�ȡo���O6 ��<�����lN߭���?�������q��9)i��Gs�Y�%��F'���?�|�B��u���W�����V�ߊ��@�\�Ѭ�'���
m�^�� �8Y,�/S�0T���"V����3�N������$Lt���T��t�P��%HW�o��e����4CE_q9A�f� \�R�^�NKcR�kAX�N���C�^�A�5����~�z���c$�D��7�pZ��L��6�/�J
jQ��X���4�m��J�ħI|��Za':�wǉu�bsL79���,�Z�]��V%X�3� �ٽ�����b��2���A�,���\�#�-P�>�l��vA3,�I���@���(��	q|��KLrbl@�dҵ��.2I8r3I�K��y�\�A�u�А-��� {!
��z��^H�b�:I�1�Edg �fh�K6��}LG�����J��~ذ(�t�ޜ�%~P1��̪-zFa#vt@+l�_���g�l����K҆Um�#`!�}��e��8W����L��g8M}\�Q��!Q�B�J�I�"�٠{4�Ē߱Ǥ� �"%�QBe�J��WL !����e�S��%Z��ܖ�{ԁ���R�KHF�<�1!�1�I�vI�8���%᱖i�C
� z$�ew� D�:�BcP�V�{���{X�AB���I�a�$���%q�n $��/H>HIM�et^�7̥k��]�,fp� ��s��x����
���d_A Ynӟ�#£�M.KQ<*�����R�$�ц�ZV䢛3ʚ���I���r�бdOh�m�è)� ��aT�_�M�bǬ;q1(��/� ��c����f��Ik�f��2�v:kQp�m�h[��n�C)�VG�ם��l��"h#�$��8q&���n���R�:!�����db.h�R���1~�	��ʚT;�5C�Z��,��;�vnf��������fK�M5O��l�(')9/嚰k�4��i���p%���D_�u}Ѹ׊�F�r�7
D��b�@�236�X�A�y̗�s�����V�B�ڧ7c?j=.k�������mUw��g���>�@��\¼1Xt�����ԉ��(� �����K��c��ђ��5s�.t�1��@�ڄ�H3��CŸ�D� �Xōఽ��>)e���� �/h!\^u�_cb^��z*�y��-]OT����b��!OA��u?��W3��hU���r�����q���o�ж�x��J��	�ƎPR*�Tn^�k0���� ��MC�(���F��dA���8DE�	�h:��*��:�V<����+�Бx�X�`7"��HpoW ��{%���� �QN�x�V�B�}g����s�i�������Ƕ$�1�¶7F���Љ�Q6]�%����4
��"�L�V�tu5�+F2oۃ��IiI�W'cg�����[%M����g{�l	������9���h *l�ͿƁ	o�
v�̱1�>�@V[����l"�I�b�%5�$���U�+k�{��Ϊ�Ho�Yo�Ь�P��S�5q��M� 6\�pk|��)��S�M\�U?V�}�`��[t��g�5��4��}�W$#�\U�Nhz;�Fapa?���
��d�8�C#f�#���$��T�y�A�}�~Eؽ��𝴘��=Ҡ�� �7rY��a�hfЂP�ΩHH�i@�"=6%{uﻘ��A)fYtu�~�oâ���k1-$��v,��P��f+� ��ʧ�$���@KCw�jJ�O��J�*�P�k�<#�lݛ�s�oY��l�"x�B��]īᇌ�,2�����%@��%�����c'L����Z֊X?�=��S|�"�ڼiM�2O�Gɜ���RM����2ƙ©������Fui��*�%����� �*�>���`D���Χ����I�pR�k��h��.�u@;;<�Z��S�ԨC��4(&�)�E��Y6:� �Eq�N�Y�7�8�Jk���j�xx{݈��E�<�\d����w���F�I�p�ĕ�ɏ�(̼���J�����)��A��,Һ,\���#y�Zs�kg�����t����w7���ՁS�`���r�%HU�9N��Hw�ؒ�#� �0���a�ߝ�Ƙ{� ������4�N{>���q��hpԥ�Ky���¥�]D�C�c�\����7�|q:����	@��
L�֦I:gġ?�B^�ĳ����Ɍ#�# ��F    ��z��|���H4D�N�©������Ȓ�h�g���*�r�o��u�	E6����mČRm;�x�p2^ݷ���{
Qb8���	�|��u�����'���V�J˓���F0�	d�4i�Y�8!��c�I<'�G���G0&eP�),*�����F�����=�J�OQ�9�8�G<S�imIrz��Z��"� �_��.>4!�)�k�Jv�+�?@t��6x"[>�T�w��p
�Mќ�ؐ���S �9�/�$�Q=�%�,�;�6�߷�=\o�þ8?�A��;�R���R����9W��Jvb��Zd�(����/�)]��#�{�� #�+���5�cu�Dͯ�wquA~/֕zc�`E�5�����c�V��_gYTs�n�I���7A=��Iw���� �Q�f�&����Y� �l�s�ٗ���GG-��mTɴ>)��H���2�6A��_�R )X�"/1�l�/G���$F�����C��GⒸu¹������g��}'����o����^�]���o=�ֻ�F�rpJ���T�F�lA{,Y@��]� օ�&U\���SeV!*���cz|�NQ���h]��{�o�j�xӕ�����1Yb�JwM�ܮ���H��+.;٢}:-�~�6�j�$6��OG��q8^�	J��N�}�~�4֟��̀����HѪ;����J;3q�|aJ�M��i�r��be� "9�I��II\�|h%vӖx��oM�+���%ݚ��Ju��h':,�^{�Sd�$wt��%�8��T�Q�٢vbO$�Ȳ�$'�yǥU�%%O�8q�c֌��rӨ����G��L�$
,h���IQI9���ʌZԒ��j&6j2bķC���g �-&J� q-*PFqG|�/-�K�Z�#Iі��@qx�P2�NiN7g3��F�M�΃ k��{|W�ɴPÑ�/J��N�p�Li��%VnP���Z]�%B`��d���K�J�5��g�"T~�C��A�Mg�ҭS�87�o��t�bBc�����S<���IvHg��ń-�$g�P�Ѷ�9�X�"1j���a@�6�^֥�p����s��?���>�'��v��EMM+�OZ��)2��2��d�Ɵ6��k�\p�KՁ��-�I�s?0A4�r�$X��HH!�ں26e�0�V�.G�3��>�lD�����t�Łk?��=��7��
'0���CEb�!�zM���RB��St��V��AT��8Ŝ�!a6���5j{�����JB#�����"�!��2粈@��p��#�KK��ǖexG?槊�N�.�{q�U3��%��䮅@�!62g��}�OՈ��;h��F�c�a��q�u���S�CYw���ۖ������l���~JȤ�as�`��8�qi���\@�S�*uG����_%68y�	�,ޞ�(<�8�s���K3�b��V�p���%��܃=5D�!ϑ	�j�ҳ�鳴dا ��~�/�<χ����f;[zu�_^��!�q%�^h�8�ڊg��)�j�D`I�J�O���o7&�U3�����uqYY�`p��VO��Щ��T���w������$��j��x��f<��P��i��B����~�P�L�Fn
Ľ+�{�8`<.� C �0*r��#�Lຊ�$>�����~ĸ��!�q���vk��C5T�N��:)�$�$���tǕ�#^b<C�F�m=,D3�G7��R�Y,���4$��0�v7�7K)s	!eQ�}�Ww��`zm���̆Il.��=!i&ߗ�y�$��)A�Sf���/��� �o�V���-6������	A>
���.-���³�o}"{�u��#�]k�sH�����.�`c�%!�C Zf,4k,s棅'�ȸ/2?����m�i�[���fa�-��2	H�ͬҷ�BIN�E��lD���Y(I��FGԿ�[�\<١�r�B��h�7s?A��m��Iʤuq���uc<�-�*���J4I�~ݔ*�wiy�p��F��0��ٛ���I�L<e�"#�L\�L����	i�1�K�D�oS��#�i�J�7��q�" �5�Jd/��s!�[HKY�iv����YdVɌ"z��p8�Z������K��I(�����V�%G�h�Ŷo5���i�bYu�΍��dMa	J�ei��E�%܅9iї,�9Bu]��.�;�f�IPo��{aЬ�M��rm�"�`��<S]�z~\FAPI8xI/�Y�>K�� �4p*���S�[:i���!��/�*���$wVE^2U��R*2pc�ӄ�q�%CǙ��7����A�SN�䋡e"�i���C�gAE$���%��+UBL&��*J�6&-����:A���y���Z��k�8�^�5�.Y�x��0�U��y��2n�%y�6�?����󒵄�qۙj,�M�Z-�Y��uƧ1�;d�q �2?s�\ �a	G�E��ֶe���Rd�!��=�ɶ������B%7m�ˢ�,9M���$+e3�{��V�
�6!0�2���u֧gI�`���LOPu��x�Qmd�%C�p���@d<���5��_;��.���2���e�d��"R'��	k ��Oi2m��~J^�2m�����%�f�h�f����T����U�6-�+cM���������m�Q[�f���5l�m!�0�diI_7�T�@����b�hTF��M���h��?Rqʲ�����F�d3h�J���Y��\����{�
�ߵ�~�y�-�(��+�A��^�D+ʐ��]x�A2s>c�JV|�d+Y�A_�r����5��1�/ɼ�캹ų�"%&�q��5�0h�{�y	l$�I�u,��7�K�S����I*�8��-%�,n#��ۻ+i�'ڨ�F�c^�n�NF�,C�W�� �P#��{^���M� 	���%��T�:���-L%�%�u8���YPc�(��f�ҝqP����v8�S�`�H�krsY"���Z6f������PM�yn0u�C�ciB���^�5$vc9��_�G]n��2���?K�Tk�z��vj�i5&�%F�p$`��ڧ���@	�tj�K��{�f�er7R�Gƞ�a't����>�T��wX�O�\�X�L�L>0�]�2⥎�O�c�"B��;ɉ��Niς_#��� Ftx֨�UnH���<t�h&8�C^q��9sT!�M�(���oE]��瑍�V�Wl'��7(Բ����w���rx͂-?��4Y�gM$���>	�e�qŹ���y�ޠl��tS��,���:��Xx�%���ǧ�1q�q�+�@�z�N:,�~U/L*J	۠��{�dv��R_�׆���& ��H*I���+��J��7� �⡫����8�7N��� 
�[����Y��jٻ�� �*Ư�ɢ�,�V ���?&-$���Z�l}~(2�/�^�LAmUbE0��~$�M�����(�/����b�!�����,Y������e�a�?o�^:`�/���ڈ�<�j��ِ���/r��� �_��x
��o�� ��21�԰��7�@^�1#�xY9��];\��l���eVu��,}[�&6�F��σ�h���3L�i�<uY� ��U��)lA�P�9�g6�J�;�@�[ ��Ρ2Ώ�E���֤�櫨�?H��&��8[��X ����Gadr�����,`zд�����C8\:�&ʧ�7���Jl-�x,���i	q�(�Dh[M�-��
��2���s�Ek^ջ���k&V!�r�t�o��b����q�%M0�--F��W]8HIY3ł�����i�@��2�W4����m�R+�PZZ��@{��b!Y�x}���_������H�"	['K�蝾�a�D`�օ@�{ɦZ���9�
�C��Яv6��Ѡ�d���[ͥm�v�D%��	$!NEzC�}�+��*�l	��\|R� ����mtOz��nv�������!X�!�uV�ǔ-ҟ��t�2,�%m�.�D�G�W���*�6(	.�!�`xJ���^J��@P�9�`��7���-�cA�"s=R�Y�4��f��<R+�)_��[`�iw�s�)�:Ҋq|f��hZVZvL�"��    ��$����,k��S�m����[*.*����v�3� VpHnK��_�$��$}y��P(�� �pN��oE�Y�b�]_�e��|ûrJ2�Gv�};����b����;O+R��W�_����Ɖ��!�c��}|.O� ���r��?�cHkF��P�h�~�[s�'d�c�!�;��hX�$�PA��Fq|i��2��[���x6pҠ6]E�)�=���#f&'d5?��ٰ�Ud:�.c#|�4� ���MA,sT
cV��IR
�N�VVr7���&��3��g�L/�=��"�PI�눧�y+�P:���J����o����ƣ���E� n�9���E��(��
�g�7sY�n=�D����}��@� %���˶�S�������R�c}�P����{�ڿT�t�������3'
�B~��m��q,FU:c�2Ø&?+yj=2=���HT��$"H�] LϠ�E��P g�d��Rd�T"0� �(��(�$�x�;����2C�_2**)�8�9�W1'+L*�
���\z�:��'ka�a���I����i���nAn��_:�Q�Vc�:8��K��(���� ��=��QV/X(�4�J�F��F^�`2D�c�Z� i�Q5�r��{��ԍ	��ݗ��R � ��d?��c�3F��e
��n�y��Du�Li]�p y��3������+�JN���h�1��,�62@�lf�^��f2?�dzD�=�&�Ar	
�R�d�RS��w����鶚�-�h�N��[��ō(_#L�u�@�d���O�F����Y�����L�G6T����Ua|�ru�.p����0��s�T���A�h �踾m?d����:�9��:��l��*ԱW�]�'��|�"�H`̄�~���g�B�7�O�R�:Ch�x�-�/
�F;�����41�^?W�X���LY{�.}r�KB����U".�E5by�h^6aKn5�@�SQz���ԀkaW����e~d�%jvg�wV�5���*���b܅�!o��W�@�Vɺ�Pa�8��w�lO�$��#Q��KGh��*!"��\B��
�j�z?�� ul��C_��x��o�2l+����8?��p~kAXݍ�^�;���R�"�we.͗�!Ii|w�82��Fq�	绕-��n���+�eߧ�L������L����T���,��kO��.zw켫�j��B�:����~�Fa��YR_��N���z�unL
���?u�_�^�I"S��v�j"-��ܴ�X܉D�o�tK��E'`������N6��� i�,E�r4�[t�(�Y&A0WHh$|)�noi>Hp�`���Z�ͳ�.(�ޏ��+$�6�>R��g�aM;��q�K�*,�����.��V�B%x[:�S�-����G�<�5�+!d�,�8}��-�j5�͑id�˸�%o{����ծ�%nZ�ط�.]"�A�c�㬐6]-H��5�S�ڟ��+��W<*N�m<��O����|9�a"]»7����N�����.�	#��o!�ύ7������S�<�S3�t���u(�戨���&�.�F���|�eC$�Յ��]�Ӥ�;��2^º�I�o�[��C�Y��Y�9$�� �2�Wc����K�%�7�D�չ����� �K2P�l;mE�J}:iFjf�7qP'�Xފ65�Hޑ}����(�Uu�A���5X>L�k���+��p����"�-u�E���G�^sҘĚ�x�A��/��},��%�~��5'iJ��1���� j��Ҳ��{�Cg�
���i�E�R>&�+�o4|7�O�9���Nkdso�}�����T�~���}�ˡ̳��[�i:�����,�w$D4@{��poH�;b}�ҿ�Yr$��W/٨Mт"m�.�~�:
�r��a'����(Y���4	�j�TZ�~�k�@E�Q��6��iɦ��#ܙ����A\ Y�s��z9H��X�����`�D���޼W;�g,���j�㸸d X���I�x%�/�����tWp�N�f��@�X=Y*�"�F��,�N��KR���b6z�R��*YȜI�C'���!�Xc"�pd�,!��iXoۜ��t0���x)|���v�:Q)�+�e�% �B��P���]�O�h���:	�=�-�6w�l�Dsi_��ħs8c^�z�$|�v6I��Ya�-%^Y��5�Uկ��@�e�0��������W���M#'�[�7S�&������ҍ�)�])\�t�AC��.KW!�^�MG(�AtD�}_Eg%�^^2y7��@c���L�D�[����r�.�!ko��)ޖN�p��5/C�wA�f�F��*eysfcP\[�!�}�5&��2?N�Ag^�A4�MИ�X0�jSh ��jI?� ��.yJ4�,���-'m���hZ�#�ciZ "Ң&�G�����F���2N���ʴ2*��H)���@����A�
al[tX-b���Y�V��_f!'"�Vn�tc�P�c��Ym�6B#�hI�������D�U‪��� R�o��r�u�Ѵ�D6j�"����A�ވ;J�P]�x:��q�JYc8��n�a&�2Jz��\�dI�]�G )�����Y���Q��E��_^���p���
�@�/��K�T�M���:�kB�+��,��I/~K?�"b���E�u�y��g�څ9�v>dԊC:��y�:�A�)���x:E�l/ȉ*D�f%���y3�EY:F�=~
�>�����\=�L���f�QAD�DM�8N��Qfy#���c��Xd+�6pa6�&�5�J�	�����X��lF6f��ZU������*J�Gʶ�_❬�N��,�zV��h���p^���ױv�-u�!�
�Q$'p�F��h����<�{1:尲OO����j�L�A���@��juC��9���a�)
����{ɇ��rKS����L"�.�9�8�ڜ��L�K/�}oh��@��5��/�S��J��[Z�4Wq��tB��y�Gw8��~�|����Ixص�֭���-�NG�ӭ��e��~z�V�DU��ELE�V�%.�F0�:݃d���˒%wtDP>��D��ܸ62#I�-�
@X�)NK��r�TS7'u�k�����:A�,�)�#���� o<�+�r� %�Z�ڐu>��4%�I�ma�|�]�c�\�4��L����[�ui��V�R$C HJR��J�8�)v�%IiZTf�=�&-�ME��.�/�w�vb�$��2����Lʣ6:r�6�t�D�k0�EG�n�Q,��rX%ݾ&D>�N��*���'Z���C6�����-�Ą`��P���+y(-��j{:)��A�,��j��R�V��Yw�:vAeb"��8����R�M����C�Iv������JK��u�h��(��3VI���z�e������'�*�`�w�F V~�6��c:K��\�7(��wTj�,L$���i��,0YRi.ݷ��L�	���i�2ī����d:t-��teY$?��\G�Y��[�<OW��� ?] �eH@�"MLx���Y�w����kz�qO ��j�j]j:,!>��	蘠%AU�!N뽾�d�;!0�I�p�����k�k&��G'�O6��o��]�\��r
S$撛WR��٩�Ug৕`<�٭�O���"�}M��j�o�f5�eް��h��8�ȟ�
�l��SK���z9�:EВ�\y�DTOZ��T��F�F�����ϒ�����c�тz�bT��}��w��tZ��r9c-�v���o[�8��CvH�aK�kU�>�/�꓊�iO�h�D%/S�rDRZ��R����AO�M�/Z���� ?J����y�ipF�%K��m86�>���o�C�2��4oQ�;,SZ�8oe��;�q�����y�j��p�K�a@��2N���{�aO��LX�-�c���:-�>��<ʿ�cNg5������~�@=�9R���Jݤ�F�d����C��5*��W��Z��zkvFy���~H%�V�p�a��8����oѺ��ﮔ��N"����m�>�E�ۋ    Y��{	��MB�eղG9d�av0J$iӏ���x�(b�MI��s����Yj�"��5�G��ҿٔ��\-�&�=���^�;�Yj�`=&�аEoKfO�Z�,-yHQ�FJ������l[����d�oE���X/��oG:(�[���'�CB8%v�8E(D���l���p!��e<��uJr��p$Xz�2��k��M�����G�	�M�u,T*P��LS�-_�۸0ʕ��� W�BA2E֝�����Id�z��y�swh���tz��|C5b�Y����Md���lLy�K֏�aY��cT=������;D�!�\Jn�!��M� �~�B�[W��a��5���R���b��׉S��ɐ�4:M����aX���h�J�q�d�2������0RQ�e/kv�~lN�$7���4T���i=���%��g&Ǵ~�Fq�4d���#��B������#�O�^W���U\���W-�A+3___DGt&� ꅛ�<��S�q��]���h�p݌'��{��FDhn-�<���3����+7^�A#?�̙!:!�Ir�g�8�o����}�5�D`�N%K��D?t��*���67��u�~E��������q�ޢk�KW)#(2�*�̽�2������A�/�QM~�<�x��x���)흨�"�o}.^�Kѩc
j����yE�R�YLnSL��i�KU��,Y�䁶��/�Ft0Z���)�풰����P�0tT��$Z{�/�Zk
�<���x�oN�p����-`eL$���	y�~_[_��.i���ly������({M�n7֝�Y����ևSt����=ZlZ�'���ʌ�jM���G��b�ws{
�.�އ����"��l�>�ݣ��Vjn�
�I0PcXC0�2������4F���<�<g_D�D�{y=DIҩ�hӍ��K���c�dS�2{8X�R:�J�IW:ڰ�G�7�@�9,[�$F2S�lg�2�G�tYB�Ekx���:�����E�<�P�M�����*�^x�7-O�u���z��GS��R����+���2��n�fcm.K[��W04dzw��z���4����V�_�ߚ��`���Kd+�ߓfh4	܅�,>��7����������\G�Pȿ_�C/qZts��W�mB�[�g����5К����h���l�*c,Q�hm�X�4P��������&;j�6\ѭ���x$�;�vO��@R�f��'��?�������x����[�w�6S�w/�H-֌*y鄌ʺ(�ZF��y��/��H⼯�ɚ�JK�+B�I��k�B���E�6�ud����u�.}���룋��Q*��8.O�i?�i� /�}���=Rc�ϫ�C)"a�L�^�xOY�^">��ɖ�f�����O�o��7u�n&�܊�O($��-���HDD���W��,aE: �V.l]������Y�k�O]&�p5��,o�ȉs��t�\�e*y�q��s�����g��d��.�}F9�&%]�xK�����æ�]S�����۲۷g��&1�{�܂�u�^z� X�C)�vH�	࿖G���c! �{����5$����m�m%)Р�f�56^��2M�k�h?.�̗��t�������J��ޫ�[]M�5�E�5��LЦ��.���r��enbUK:��E�:h��=Ѭ'�(��op���o��S�-�m:��B���<0pU���e�o���B��*U{����ę�~UЍ:�\~Ô�F1��@���Dk�o��?��ghWK�+U�t���aR��!y���%2U�6��9�9�"
a��g���A֮ś��!���4�ҟ+���Iv~�qѺ ���=����,��[qI6�L��XZ�h
j7�Q��f�����m\�����l6R �_+q�μA&�d��VnEЦ�R)_Z"���ڬq�d�k��K�O��Z�4C֙��.	z�F��_�dR�⺸vx�65�6���N�VG�!Vq�%���k�M����}~qZm�H��(�B�3�Q�D2+�"���ܔK�Ϫ�z�(��:~�'�]�<�@�f��
�x\�_�����X��B~^ ���uV<��_��p�$[�%m9;E�Y����2 FcO�����/��h���>���hg�~S�{��I���3i�ҝ	٫���o29�7�0�%����R'���8�I���ѳ� ���di��?D�-n�9��/C��+a	��L�=��PZ�m?,��A:�]�pc_u13 ��m���ׁɓ.Sr�a\�0�׮���vdTR��m�/U:PR��k�.%��^���T��NZ1I�Mқ�kO���0<���ä�H�h����I�/v�Q��5�|���9%j�	0��n���܄��%>�+�It�GTTI��&���f��S�r�����Z]r3�y�������`�Ae���'�P����A[�\�������~�(��i��lվ׾�ud�����0l# �������$�������;T��My�8��4��e=�˵,�o��R	ϵ���\�?K����s�>V�3��D�2$7�׭J�R�c�?hٓaOsFIb��7���\������^j��Zo��t�Gi�&ر�ȥPI�5ø��,�d��[��d{F��R^�=u�b���(�U{k��e@��)�)ϻC ��T^��Ј�s�BrR����8��H�����cΉ�-ue�Y �Mݿ�Il�pQ�i���8���\�Kf�T�	f[h��єzB�2��O�id�H�f��ڙx�\�J+Rv�:qq���E���I��)I���W.y�kK6	q\�F�w��6L�M' I0<b���4�ܗs��*�~R�T�� �X�e1'����9=eU��5w���
<H4�M�%��J��.]I��)�j�S{� ���u�@���|�����d����j���n��Wj�q�O�.⣅k��vX_�.��z�MX%'���ҼƧG��4�nƤ1�2���ʚNl[֒��iz�E�y���G t}0�,�u��&��v(Z�������Muۅ�{���Z���:��W2�!��h��	���F�.���$ʡ�h�coI�u��4�w3�-3oE����t��&I6����װ�/]�5��1�$��A�!��7�{��κ�K8#'�M���Aճ�+ ؜)��5��U�,�q�˵�[Z_�~L
k|x��M�G���2ex�����e)���{��A��fT��ZҮ͡kl��Y��=�r�ص7��X?y�q4����)+����[��餸�g6���cAxޗdfSUa���Zoɲe��&�����-���('�1�:UOB(>7	���:2)��5��{6�0Is=�P���*�<D��@R2�(>�.�+
��s���Ag���ً�.��)����l+gy(ֿ�!"B0n�?�6��pȰr�!������bϸ�j�ʎN�l�.\���մ���w�<F�cy���3Sު+�p�+V��d5�GNU%�C�J��Tm�ޛ=I�-
��u�Jvn���y1$=��aJ�5��F֙~�d3�����Lܓ��p�ҹ�&Su��s��wi.ϏEl��^��d�AK�@彽�K�1��+����s�%�l�0k��JM�#S�2Ž���8����yE(L��S�6s�ћ�1������Z9�y�{�u6�(�ҷ���n:�E�$�/2(���o�o��$�H�2<;F�n��x`�:�GJxkn�����#�GҺw1�K#n�_Џk�[�.i��m$F�.!�q.���3�6�R]g�8�_k~��w�-�]f}rmٙ���dO&�����FPb�\O�J����,��u���^-�mʈ*��}y2�h��%-���y렱p)S0���o��k�㛫_8Iz{�O(*�F{�L���d"W���S���I�{ց1{�F7�񅢬�+���N����� �@Bu��Ե��#aw1-�����2��'����'Um$Mi�iih�!{6J81${��M�_�����#U�[�t��*ZE�:Z���	<2��!��g�^5�BHf��O^	�t�b��LT2O�w��'y��p0y��"��n�����;    �@F}��0T�<ȶMR��AI�mmW���=���TD	�����ej��2�d��Wu;폲̥A�/��H���!V��-x�̦f^j
�A�ߞ�|�7Y�*�XB����^�
���8�b��_6/E��7���@��./YJ+Yd�uS��j���C���hg�L���-��h��+D�X$�[M�]w�SB��-����5�ĳy:�T0��@T� ųY	����=J�Pƌ�	|���M�Ii[􁝰#�I]@�EX�IR��r嬼�{����͛���[})��a���j7��5���~E�<�%�)�P���5�z
ў��Gz�≶F��a�?W�����9BK#������Q�4^,)>�{W��۹�������k�--w���_WZ7�<\������c�ɨFUz��Vd.8�w,��p8�fB֦�5��$<�n+R|/b��aS�c�xk�~d7�џ��|�f_�#���8F}��.K�3�����S��6��l��N��,���vH�`��������=Z���-�CW�n5<K�`�T	p��nt;��'��-⑒�&�*���ʻZ*���-�D �=����E2��"���𐩗m:^g�7��N���j_o_NZ����3���ۡ�ְ#�|Pܶ�Mv�ؑ�9R��J�=Z���dL���x�m`��}�ÓH�̯E��-���*r�Y�ܳ���nTX�6ÉxX/��A۞��֟�g��7��H �	5�[,+��F��H�H������C��A���t��'�M�4��x	C�;yW�DJ3��;Ql��'La}�nKC6����RT�בz�R�Xz7�VD;YWzk�Z*�7�d�+�!Eq^��]sӗ��5g�-��w�~���*}U�� �ܓ<ۛW��1�{mB�W/��u/�n\S��k�=i/ҡ�xU��5��&��O�L��%<�L�q�����3L([���l9����=zs=��8x{s~/�v��~[T�'�h�"4��.�I�-H�QplŘ2��2�P#!�b�{��m�|�w��͘j��G�8Ϧ8������Ux�ǒ�K��ߗ͢߻��b4�����dU��o\�ڢi�$8]�'Y9�m�(T/u�謉�of6�@���ag���G|�N�G{:���HO��i�+զ��j<-a�B���$�x�𾨭��:6�u�kf��"]`$�0�[{��8��Ot��4�D1Y�O�J��[��zш��]yN�H�<K��,_�OE�������/aT�F�v����2���a�uO�pdx���ZYa;^BK/�O�Ro�^V��Q��D��$��I�md�6����>�1������&I��6��qBi/��T����(d�A�~E��>뒊W\�s})��}3���X����lѤKÉǯ5�yf3or�kj�k��n�g�)O�#[����:�V#�.@LG�8�����Cz�u��$K3��f�����"K_���j�����:��F��㟷�N�N'���ɹ~�O�����ūe}g��h���st���1_���4{�G�?T2�������\� ���|�CR2���e�{��*&�E�����'FDIg�nx~�-=g�,r�[t�z�
����Z�x�ζ�c�D '���tV�>�J��Bk;e��-�u{�a1�4_oVIc<`3S�#�A����l��I���-6�{7 `s����%)�Yu����f����G�Y�}�82�ʡ�~V��9�dC�\H��65��D�DE�l�J�<�A@˦�c��a�=K���km�����ފ�;=Ń9�� I�4���ޅ�c#?O'XcM{���Jdvb��_��&sk<�!E����yAM��A^�O/��皀�c}������ɨ���s!:�G�t���	��xQTģ%X��|�t���ǒ)5���]/-i��U?�m��1��)Q}4�n�Q0Y6���f�w)_�ƴ'Ƹr���o��<�(�0���4`������ةNtb���#��r��x��r��k�~Z�Zr�|��AB�74쐭OwL{���aC�G���I5bJ8O#L�����5683�nOF�����
Ι�OTA��7�j��A�Ӟ)K?R��8�d��t�קU-��<���f�G���w���S�x��!Wr�~[�eCa�ځ�s��s��}�����zv�yk�����x���Π��j�7tƧ�Љ���^�'=k��Zf��=Z���Żq�:���Px�֖�R���q�Kk�r9����$���Y���.����#%u��U,{���u�	is�1J{x=����͓L��{]�֩%)�.ڴ>Z*����:/iY���:��$�H����%�޵��������)��<�!i��Gd��#܊�7J@���ĩt�ϒ�Q��p$�@�^N��%�8�#�pK�T:�؞M<�-Z���f��-��QVÏ�+]�N��B���p�C��㨰����|��l��I|��9��^J��m���;��6��<��^�X~"��ɟ�7qN?M/�&�ٍI���j��qfYI ��L�l��Ncg^B4�@7�HE[@,��[��_[k�=5CyO�S"��Gb�ֺ怢�-��,����y.hgK���{%r�^���� }�����it�ll3m	w�87uHս����I��rx(���ٰ\����t���v�.T��_���� I#Փ���=���Q���_�.N��������~�!lT�;��N�fJ[)��5[^g�H���F�M�I4n�n�Z����V���l}kO?�8���k՗�eV�
��X\>��p�xo��D�'�ȗ絎��<G�^b�m=��iI}���ۊ��ھ`SA���6�&0\������Hui�ց�~,#J,�t�yZO�[�*ހ��??Gd�@q���j�z&v���]{{���V�:�����69�nŰ���{�p�4a�6Ρv��*$y��� ӊ������	q._�%��S�����xy�4�����ѵ�חWo=o��U������6��/��Q^�۸�cE\g(���b�!�S�+��&iBG�dpJp"[Q^�m���󎶥���������k�ַ�K�	��of�Q��˴��~�D��EÍ/�������>&�V�,ò�o��l$��B�X���y��셧��im[�d�c�ɄN���=���F�f��G7�_�.���+d=�n�o�n��;����V��"�@�f�p,_�u�y�@n�o+��x9��V|%T���C����+ܖKc�H���פc�=;���<�	5s�hnn�pF�~w���.��xT����P�yn"Z�
��X:}��ف�4�m��[-O������G�~tx����M C:�d��̾�_���;�YC	S��*�A7I�p��H�NskKo�����m�k�=����&�;O��t��7���V/��Z��C��k���zz��!��W��(�-
L�%�<dOs�S]��Pr^"5�qI�tW�b�s��W$�[��L�7L{܌�-"hH�஬�\� ��'�E#P�
 `�I�,���|�f��=:��Dtq<sJ�GfҨ�[a�!X���k�@ΰ:]r����p[�,��ڮ��8��]�AW�-W)y3��(]�h������"9�����/ς��)��O�*�z��/4˝��v��ȑn�2Ou+�b¹�YN�\'h��8���1钶��;��D��T!�&�Y��l�i������^V sk�������U�ӛ?�ʒ=[��A��p.�c�<�bxv�16�Z����+퉌AuYz\F
����iE� ����<���U�:��J�	Ɋ�~r���2+���z��-^���C���/�0j$Yڼ�ݟs�湒�]��D㦧���K�Y����HVa؃ e���W����L�g���h��:;��.��栴9x@�v鈁��g��Ew:�BWk�u�sG#�ӭq���n�'�,�>�=/���p�&!� ��5h��(@Y�M�wK#ݰ�� 7�{#��J|�V:d���K3ݫ��2�1^�aO;�!Ⱥ=��l�7���d�r��w�l�_�4��    �����o���73����ڢm�&(*��nȋ����� �{�l��	�qD�g?=u��n�[��r��+��ۤ��g��V��b3+�be,�j�"�?��E���/4����viI=�],�g��z(�^�u=m��IٿF�c_��sx����*J��X��sw3G�;\��#	@�[4�=Te�x����
6����x]��ܼ�,p��i�6He�J�_Iv��Ds��栍�y�$�������O��]7ӕ�zGN�oR��qĔ7���̆� ���Z�����3,���_�uvA[�)��*	�������6,���FzM���D4�C��٭�V���@
�)HCSc�`�8�Zt�<��ʓ���i�K��k��!i>�i�;g�3Z�U+z��nu�-Z���t~K�)��gK�����UGs%&�|����:{����m�EJ<)fKd(xk��	��օ:�W/��Q#��@�}9���A�l������!)���\x/
z:��|�\6O�-��=��讑~�2�t�ɰ�)[+@�ɧ鮤��}�>�O82����m�>�iS�n
�;�y���Gʅ�:�t3=�����wwV��%3ۉ��/	b�j^kO��M*��
�)�4|v������ѤP�
��2�3sIO4��liE,HuH�mEp�jZ�N4�歞�����a�O����HK�` ~��aI�%lG;��� �2���[��"��^ˠE⹛:�Y�C��h%�Z��?#�)�f��E���_WSomxE��,����4�ff�RCG�_�vʽ)k��?°���)ޤ���>j?��/�e��h�^x��;A�U0��{Ɇ�,nɨ��%1��2�yH��#�teP%�32fd
O�
������ɾړC��M�9�pL+�+X�eQ��/�����j��}��xͱ=]y�$FȤ���і�g?Dɳ?վ'A�u��;��3٫5�@����ۥ3��I�ɽ�2��E�8έ��ּ�e/O�����ּC�Tn���9?��%[>��M�)1�A2�6���^�scќׅH!N���|9Fy�u�z�1�\��tS�Y��}βʻ`�X� Ӝ�KY���Z�/����I�/�ad�h����;�`�A���ڨ��<}b�3-�G�^a+��_���yE�xT��g!ӡ�8��n���Y2�R8���ˀ&�2�����\67(�2̼�ô6u���N�P��Rѧ�~�M��vp�0�b��0�24h����SLO*�aT8[�o�juL�:Y�ꤽ��u��_S�s��션�y
O�4=+�۰�-N���0�nF������8Ӟ�����g9/�3/.�!�\���W�H%Ƥgx���S�V�i�[�އd"�>xDǫDE���8|�Kx�q�N�AH�a~4����X�U�kKK�D��k���̂����a�g	[��#��u����7룷�0�S�����'7�����L�E9�]mχN���2.b�������Z4<G��N��յK�X�,��5����I�]<]������&s���+���﹎�>�T֌�(�v5Yp�K�{N-����V:ـ~�����0d���1���}w^���/1�>�^�ٜ�5yc�
�e����Nt��uM:��{&�pˌ]&	l�%��'�7D����`�xY4�8�y����*��
ll�{� ��_7��N�ì�G}�������b�f��.�^�.}O�0ʃ�~��d�YQ#s�#3|57���ǘ��{{��(�N4Q�a�i�:1�h?�!�b�%X���Ji�K�F��1Mml�b�T>Pǀ���s#��0eK���k�: Ɂ��(T�wi�&~�Y-�SZ&��H4l����9�N[a@3�_"�}%]��3����6,�<{J��b���7��c�>��_�붢��yK���0�����rZE��{�x2���CWK��7E�=]B�]yS(� 4�(/=���Dy�.~�_�:hqQ�v~�c<?s9?�=��,(���O��jT��=�~�oGʄ�g|{�H�V�%ozh��ρf��Jx/�vz[����4��z��6	���N�_k��i�+�S��`���(��+d����V�F�_
t)���h��寎�{����O*/(�A.�x�)�(lC{E���k�C���I���`"/�t����2�?���3iI~�m�͸ 43s�C�����c��	9��u�ٶ�H�}j46��<�?�֧�7�Vwe-�����C!}������*ױ2��F�݌�\e?�A�U�v⩦w?p��HM��w������2�h�'�lRo�����@�>���� 
zQ�ys���  ��h� �ʾ7_������bm�t����/� �\s�fpb�|�k�-����A�y����|/3��	���
���	���/��^W�Y�|ȱ-�&,r����2�<jj�5�;��>?�'"L����%�;C����t�+�Q5JW�����\�.ʚ��Ԍ��+�C��E�vقO��k�@SCl"���:����,�m��?A>�g��))D}ܥ�r���&r�9��]�eƻ�r����]Q���
,/t ϰ��(Pvb�ا�`�����O�(ld7��_����(�M���ߖ�8��F��E��}*ԟ�w�rwc����,;d�	7�v>�gf<�q�@,{�%�FO����%g�]�Q�c:�E6�L��+�)�r_��>�ژ�e��7�2*(XG`��^�;���㋓���mb�7|?(�u4�ݹ��.�9��u]��<QW�%���Q=��!��o���9m�/AO��;�	�ȟg��E��(3ߚ෴K��,AA�Mpmf"Tk��?p(�{o���ONɋWJ�`D���f��-�Rhi
T#D%� _p��E�HS [��>?�ѧ�ʪ��D������W��28ob߆��"���z�H���4X���ɨ��]\�:I�߬�����LG/�OZP��Hm�pz�h����oS?��l(� ��xD���t�Rʵ�p_�^DӅ�i�k��|Q�)�O���wh6��~9>_�������`��Y�c&�7&C��?������@�vL��J;��-�~'(Ty�+Tr�{??��:�Z�do'Y�o"C����ؕ-���B��]�Ь$S���ꕵ�y^!�; bՓ�ܜM�o�}$-�S�%�g �O����Մ[�N�L�hEwX9�hcO$Q��2��ge��i�C��tg��U�(�T��=hN��	͡��F�>� %���uo�f����>&#�����Ө�}*�;��v�Ec���B�2�T�cO�3j���[J�=���q�i� <�@M�)|P_���;��|5���� 1h��o]���.�b8��@V^���V�%ē�!�d��@��} ���!r�(�NyÆ�����G^�\�bl�kP	f�خ���>VG2�0I���#�-,�^�� ���d�l��=����#�-��):���Hp��Z��S�������{P`��@�!�県ps����+��������d]�����@�K����v�A���D��ٹ�G�Ց���+���Ց�^��N|~�#�,��o�~�w��O5�!3���"�Ց�.:�i����p�[�#/�|?n��0�a$�/�[8ѭ`5�6���	n�wȔoz<�q's���̇K��	n�{���	na#�/\��-����-���Np�23�~dڂ[�i�
��b��p���^���&��q'(�%}�,Zp'���Ӳ������:��
���-���$����q'����U�BH��-Li]ѿ�襍��q'�ɔf�^�\�Ld�K��?n����ڇ�7��Npϑ�gX��Npg9��Wu���Np˽.��ɲ�p�[��������-r�T����[8�-|�g_;�?霛�x�n�����8:Ƿ}� & �	n����i�`$���»~�W�n��i��d�,���p�\@�� �~��p2��$���xzn�����������`^H���H��jN4���@�h��`�(z
����OF�Fn���%���Uw��    Bf4s�R�r1�R�d�WYն�%�D]��L�v)�=	n��|ϊ�YE2�����
��X��:������D��E{Y��vJ?����-G�
>�����X��܈g�ɉm�K}�ܤF�(�3[?�5{'w��p�]�^��ǃ�褃&�/�=	^�6e�QZ��L�+�ٔ�9v�+��V��6v�Nq2dz����^�����j�����HXX��F��4(?�E�EC�����H7yNm',*|v��Z5����X����F	���F��d��hTG�b���^#��a�X:�h4~��0?L�Dvh��͌K�.�8QAc�(ĵ���hXd>ЀL��ۭ�4��tF�>n���h�V��������<��-�R1���T��:�=����k~�DT��+q�u�����	���ZAz������{,� Ǎ��K�3�� �==u���{D�����s�6~���B1{K+�82����M��R���筺��-�]�|���,�W6����K��GӠ�M�UC� c��AFV�$:fg��Z��k�LL�£���(�Yc�n��#_첎B�Ds�:]NuGaX<��d~�N�L4�m�T�˝����ѡxo���~�N�`z<��bȅ�|-�E�Yd�b����p�5���>m��M׿�T�:/`�y��+����j�����5�p�;����D��o1VߚCmv�2����\���f�����(~���LX<�+��{����m�2��Y���Kx|����Q��Eol$����(~���" a�iQ�B��MB�y*� ���kt��U�y�ƫ? � ����բU%3���K��ڳa�Tp�޺�V8qe<B��gJ������T"����n��&���{�	�޿˻Ⱥ4{�*P�-�&���px���c�[�;�����]��n�CtX������ڱ��K߃3�"k��ŨrI�'O�e _�>�=�8���PFz@����7Y>�v ��c�q���9�$c?`8[�X�/me.A� �V���塎��ǃ�Խx���}�+��);�W a��]O���vʷ���x�2@T�B��n6�\�aY�y�]Xh�V�L�nKz3�U*k��r:�3�i�՗�cN&f�T:��&��Ve�#^���rf�
T�k����#�h�ӂ�[G&ϒ��Mlkn���"�o� ��>�dE]�'0��[���o�AK�
pr� 8�w��7 �9<}���/F�Z_�\�s2r�(D�3��>X���W���?L��_���8�w�eNʑ�P�������=5a�~O`H�(=/u+`�v�����-q1��|�O�g���mT� ������P�sn�+pV��Q(�cGq,��ط���P|T��}��v�fBR��c�! I봚v�cW��D�f.� �j����n�t����,����T���O.nT��� j&�9����-���C3WZ�U+�A1!��);X��~H_��;����~[�|��u�4�1%x�.
K��3I��o+f��9�x٫���z�u���g�9y�vþ&�ղ��^���2a�[�Ǚ���R+�,�+�[��۞{�����	'�|̓����a�o�9T��5��r~V;i��Z�x��G��|@��(�{����K�Q����q\:�CN���ty�r�>���E2�F���:�&�$����?S��HF��oQ���N���gy� �g�`���۽~�4�NT,Δ������+��~o���_����%]V��i��-~^|H�ix6{P�9:�.3��G!�oH����q��U8vA�/h�	S�2�o�D�q���!���۳j�ᑝ���/�M�aD�"��n��ZA7�h�ZwG�k:����2�g�d�-�;7X@w��ki|�=]��lK{SNH�΀\�i����9�����}~ٲ�X��;��'�E'B�|�O��B~��z���U��|v��t�S;�M����xqcw9�<^��4pds��M\$\P_��:��E{������:��j�a����#�oiE l�T�/�)Q����b�_�ط9r�	�^���.�g�'KRj�iy���R2��-�c��6�KS��f`h�;)4�tk 0?�	C���92���&�J �G��e�^��x���e((e�c��� ��N�&
a�L֥�九����Վ��$|hd��>�w|/�5r� 0^�]z�I�ٌOb����������Bk�j�Y���U�}O)rPS{kZ��~�S�Z:�`�߉3�4}��~��b�0��e���K���Q�N����L��F&T�Ǳ��	��)��OS51�:Ä��ĈӝA.�`��t+tskI�"8��_G)��;�<�5O���i����=spӗa^4mX�v�:���5��h��h������V	������m���wm��z��[+8�	���Հ��hDM�?����sC�����S(|����o3��AK��l�wg=���X�&�Vw�@��}���W%>�w?�]��m\V7�P�/��-���Pl���H�ExN��K���%��k��0�����k����C�V4蚲.������B�Z�[ׇ���(9?��r%V��y�y�; �C�����izJx�2�ݾ�?��C����݂����Xډ��sd���N9��u���*��K�����E+MVM��d�\�I��}�� t��]�xh���JL�Nen�M��Ci��,]6��+�ɠ*b�&�:/���D���ڣ���hG�װ��j.��r���H���TH[�}�-���hX,�g�d�Q/�ŉ����D����s�Y��h�՜u�o~@�������I��Z��Wr5?�+���o�#i���ݛa�/�D���ZffIٍR��V��B��u�p_M ���O&R���^�������{P���:��I�� h䧲��èNU�����m'���?S�2J�z��me;�� ��W�^��O�d�|l��	�:����-��^�7���a�!����� }t��� l��ï���X#ߚ�鮋�����d�%H���Hx��$輵1�^���(�V�S��Ĉ�AxwHMS��Qi��޵t���ֱ�m��ٓ�����m�������xX�ay6�Ps����>��\T_��|�aݳ��F\ڃ�Z�뉠�t"������q�V�޽'����X�I޴��q��� �#�Ϩ�E�j�o*Nw��m�F�ґZ�S�����dky��Y��/��=����q�R�:Dh�q
�q 誙 ��_�,��Z��fd�W4��S�V�2���]-+��ꌋbW+�	���P�r�h�_�O�Ю!����_���j���M`���k�}?�jP�}�����q�Xx�Gyː�f�Xj��zԂ�H�� �ƪl90',Z���ڀ�/���A��� �2�F�h�<��2|4�.Vҏ�9������˕W��G�VgE�ǔ�RO2��E{'Zl�
��{������H�4*�?�@͉��84�D�������US��-O�X�{���_0�2��Z�ݲX�o�sp@1�ӂm9՞�-wu�k��xk�&�v��	�8}g�8�Y�	�m9��[@	�n7�
Cɨ��'�ۧ��[@(r-�=��<07�z��4����� 8{�_�R������/�#qp}�U��3�eF�AD��;�:��̊B���X��?�+�ey��hmeC��hI��@Ny}�Đ�Au������E���eT��{��(�wR���{Е��]��Ln����]֙pX�
&�����~ǋ7zc�c�a
� ~��Y�����7����Z���OB��s-��2�C����)���.���>�B�I����Sv��6}%���/�-��w��MU�[(h���� � :Z��V+��=e�$hK�r{eDD�ݿ�jӗ�}t�qmG���� ���y���"f�[=�̃�Â�$��7�z�7����� ���&�5P���a?f�Q�מ]�����    .�R����(J�w:�W2���!��ڟ���w�Ⱦ����0�ǫ�ر0 ;�(�����9=\��<��\�"J���Lx�Zd}�"4㏂Wor�q�H��v�����	v���_'���U{��S�e�D���Yvd�_�םh�zL�(�49��mD>�|�Qt��5d��]��}���ͣ܂sE������k$6�O��TT��O
�S9ͬ@w\P�;
q��0>��y�jF\F$�t�������	��;~����گv�`�(�QF����� �qb�s��;�6TK|('���a$�&�mO���-���(�iK3Ïw^EkX��8���>����W�DQ�	ߺ�	��2 w��2ʒT�93��]=	a�Y}��Ý�����]� ��n�'�0(��-����H���(�fN�3J�4�M�h�7o�����sd'yi�[[�M.��X��Ƞ!��om����4�Í"�+{����C佦e2g�hN��E!A#��{�>��o3°�Qv2���,�W���;t�dv~�-v_�9�3�-8*2��E��$��k���\�}z3,ob%������1�C��)2P�7AQ~�}�����%��TĚ�E���I����t�JLF��h)�r�h�y~V_��9���<0#83}��B�-zP6D�Z�:�ZήY����Ļ[��e+�݊�Z�W�Wy�8��mˀ�@�1��
�۪�����3���m���M+K���t��뼸� N4�{�b.��d�vy,�t�R$\�M��j>��#�"ǈ5������o�����_S����YB�I+x�
�OG��N7�f��j�>���*����"�9�M�DP�|�;��e��E�R��C�m��'��̩�)�_яu��,͒!��R�0p�iy�v��Jy�kC�ǪS�g�0�zۯ�/.�k����ŻG�l���F@�}m�?�[��6�Jl`�`����k��誓4G�=\/������+K�k�\{
�eTH;D�M�_-&�
��w+:�LR���x�)s��g�M2.M����9�pix�)�]i"3��D��AUg��E��gayl����GW�vz-���� <���SN�� �l�0�-rDLW&Q�609�R�(}Ä2��)W�;�"�.��k������:�\�{�[���l��K�}\Pl��k�2��L���U0�#\���	T,��e?�|�+0x�	�:}�H��w��&��[O���dx�o�6�NR+�D�\@���܉���h���]���=�@#�}����{�^����cm�Wp��~�� ������-dhd� ?��i{�� �p��+��}O� �ڀk ����(d��If���v_ n���3#�?�,�?�3���RZ	��!�ސPb=ʹswك�f4|
�U�a��\�R���I�n�������鳎�z��pӉ��c�ac��d��6	݄ϐE����CXg-���W����Cp_�Y�Z)?��}J
��k���~[�n�[�U���AY@i�B��F�q���s�]�-'�x?y�iх�U��!΃j��G�ř�������C6f�6�@`� ^�"��ݠ��	�z�� p M��]�{z�\o�5��㙰,Z�*�V@������(q����C��"oW"���<�N_ $�gRu��f*4(�'��yL��	=V������ j�G,���2�.2��x�o��9��.�#G���$JeaO�G�2�I�W+FNO�k�0��z�~�C�{f�V�2GK�E|^�䔂DXGv{N
P<$�}�$}���m �8}(Ԅz��ը ~���G�CU-�"|�?0���,��S�\��ә��،�˲6�����?���-�d��La�8�۝u��4��_�,���Q�H|�܉��#���yjg��@���X�}� ЛD���Z��O|]c~d�ǆ%�y��86���R��%N���Of����~�ݺ�8@����(�B"��\�)u̻�˼�7Z{L�}�	��z�R���F��v��~���W��DG֮�F��rv���5�Z[�v��w��MP�z�C�Nq� V�X�z� �I�ɣ�a�:��?��v�.��91X�)�Z��HQ��Fؤ�	Pe�^����Fq��HG�#<�E�.��n]԰kOYGܢ�CB�F��l�}:�������':CDJ��/����@���zT��C.�����p2�0|q�;��9�?��w��YAc��Hqh��`u��9R�}�8\��ߑ�K3��lg�a؄ǻS���L��#�����ZgX�N�$��G�6�&,��̗�|pX'��}};/�ZL*d�U��r�(�f�+�K�t6�T�	�V������� ��r�)�t���2����:�Z�g%����^9��md��M��&;�2X�����wF�y#�8���wY��m�	>�)V`������Yt>�j��7��rq�ׯ��=���{l��I���0<U{����P��J�{$
l�Bo��a:{ޏ�V�b	d��]�d�f�!����A����J0���Ά`�c�"n"�K���p�xo�����^��3IT������1�$�j��sm��j�Jx���>�3�+�[`t�kӸ���*�pf���H��d�:`��=�\��(�<�?���D럻ɞ>0IC/��~�<��&l��:�H�!��a8����8D(+�8n�iMH�rv��1�1ʊ�ҡw�a��<2�^�sY� �%<�\��4<��\���_�R47��p	�s��5���� P��E�k�Q�{�&ܟK��.��q� ��;m���6���\�܍��i�QH�!O�#��kٚH �&<w��Ke֜�$>��K&iU��<.�]�jV]uZ�	��S+��W��pL�1���9�)�8�L8�=rv�q89\�t���j�[�t�ƀ����3R��R����7�Rp	�+\:ר�YC�W�@|�W�[���`�:_=�Ύ���{�V(��U�6��#��^�%�?Hl>>�x�H��$N�;�䱚�&a��u��GI��&e��ʡ/������Ϩ�RWw���h��
5��Z�K!� ���i�����f�0�*��� %����h��Px��oO;T�"4�OI�6`~t+������&��U�}쫃F$��z� ��}<Ғi�5�'����?4��57M�$���i)�:���e.��^5֢�V3�ٵK�k��T�n�l�+$�=� Z쫐�J�,�n壛�+�F�(��)Xg�eۣ��J�����F�"�����g$��g{���i%�8pld<hk_fP�1Ԭ��nK�Ŗ���Zr|�Q%2�bpI���r�| P�:K~�`����`ŕ�V��ۅK_�XJq�6�mA�@ޙH����74�Bh;A$��٥��?�^�v�ݻ�������@�L�i�@%�P{ҁ?�qq�x1��w_�fhJ4��<���f�*_+[γ6ǡ���(���
W��ax��*8� X�P	���m���C�J8�$GB�+��!���#QZ�w9v�ap}�yY�"���L"�Y��ݹ�Ś��o�+eFP��`Ȅ����ѧ�L8T�k�Ev�m&2EP	gy�F����LP	��_I��q�C%��xP�]�J�Jx+�G\r�G�]o�q���e����z���bg�%�)L�����7Ҟ�C鼡=��Qi{�d���������XrL��Q��O�x_��8�xq
R��G�cM�D��u�5����,���Jq�X l�
�oyL$:�$Ȅ��J�l����/���BD�[�UU���-���6 9sT���5�p�?V<'�G�ɄA�閮oI�	�$�3P��~	 ����L�����t��3*��W���{��p��r����s����$O�M�s��2οM�_��[�ś�=��gih^��u��F�	f������C��_t��~21[�4%9��p!��J�l[4{�(�𸮗^� 9����rO���a`<���B���ײr�6�T�'�8+~��
N��
�F�������!�u�    �� ��(\��+��L��<L�LC�n'W����|���.7!�3���utF~�g�`��P'_]ַ��r(��)I��TL�{��%�c��|�ڌ�`����<��!F�e+:`A�p�Q���5��V�Oh>�>Uy������~��ݏ��{B����a�ܞ�wO���I����&��}�.mR��y�7�
O�W��HQ ���i�e�����pU����|�0B��=��
YW�3���	�
��k�����/	5sa��/<+�g�m�`���=���G���
�����jO�Sބ��ET�X��#��;
�_P3�"�ur|�Xt,�gEb��
.���Z�1W�ݢ��|6�.Z~�v��'������W-���U�.�<�o,�� �p+�&W�w�
NO�
9���R�HI��Vg�~�a��a"2�(�R�o�"/v��	�𾮜!�:���F��喡'�
��I���4�(�_{!9�.��:��a�t��&���p�"n�#��uyɤ�L���a:g�~�pO�Si�xF��}a`� $-Q��=h]��*	�a�CF��t4=HV�S�JP
#(�]�&�W� ��\�kq�.β�n�j��R᭛�rȭ� ���,�����S]+��rx�1p
�y��(ӈ_�d���_��)t8��G�W?�qר��)Z:P�G�G�a�џ��P:ֿ��>�M�L��*��k�N7��&9ymYh�\v����tH<�z�p��������:�m�3y�����Ƽ�!�Qm[��{������`@����J��#��M^�=}
ϟ [�����^r13��W ��>��Y�?-��Z0��$�Ş�ȃWxA?s=Z���V��KCy�:���r?��k0�p��^�Bl�޿a `��N5�m	6�Z��.�J����X\�\����R��)'T$#�����,���=�e���Y��ż��M�; �EܙuÚ��`ט�l��>5�D`�P�A��β���9�K�Ũ6�{��o]gӞ��v�������\��n�y�25W�����UQM˙��J�rk����[;T���#e��o9<���앱�S��`{@���|~l�n�F%��K��~��<��� �W�<t��B��ߧ������A��.e3]f����������\�G���4 �����o��qc@6��r��!����m��uْ�v��{ǳ潪��l��ۃ��	��_�a�w��fp8P�g@��w���%S؅��������l[�A����A/��߂M��;zV��uT��ـ{4����>%� ?��(jӬ[98P���O��·� /M������c�\߹Rҩ�W��m�Ջ���@�,�7D%A�� �<l~����Q��D[�zᦥ���ZN�q�^�}��~r��E�Y~C��|f���㙡�N�����5cMy�X�V=L��*��R��	�k��2��F �0txw!����45s���)
�4pG����F}�)���DS�jTy� ��|�]�+�Չma�	;�!ڄ����+·]xhkj?�=5^��y���ő\p��I�3��.����%kNU�"/�<���Y���&V�C��" ��
��*S��6�&�bFB(����I
Ё�	���t����k�:W��(�5�ϩa%u�<��x�Ǆ��Q�j��``%��iA=Hm�i����f�0eM
C�+Z����єs���p�A�=yz�X���Wa�wxeT�������[�p_O<��'r�P�ٞ�Jmy����ǒ&����*W�k8�ʞ5�pW�z�{NE��Ԙ�� ��~h P�����s�[xp_�>A���?&������A�e�CAG0A�J�>�N�	p�֚Qh�˵��Y����o툨�����(?��n��O
�9ȅ_ ~�M>S�bT �U��v�灴�[X��&$i�[�p�3��h�:��vw?+�Z7������N��0������0�O���IH�/`zx�P�з�4:�1M�6���d?�,��/�8�LwP��/ BٯO=_�� t#ީ��θ�D�	`@V��=�*ZT��kݺ鎪=)����\��|���OA��s�E7o���=���Iɿ?�B�`ekJ��<#b$�����7���Ӑ_GEۦ�ұS��0�Z���O7���]�B,��{C�F��#����I϶����{�d��B��P�-��0���YH�0��5���lCG��O.�J鴸�b�nH���`��X����B��T��}��c�ZOe�jt��+܎"�FQ�ذ�gև?���#�氝٣��v����L6�BK72ˈ�.�9�b�'�g:�gg�k�a�X�kՑ�0Q��A,�>��L��i��'X����%<z�������߿���ѩ�'���~H��Eib�b*�t�M1=@�K������u�ݸ֞��V�g�@����0��|�Vа��kȻ�=m���x<b�!����䞙|ky5��^�5��/��� \�O%ʃi��[3�hE�&�X���ɿ�6؅	�O�S^�d;����

 �dMYS�m�J�ے`�e�p��A"��rk���,������d����,�=�:���6�$��n�4�/���[ z���ڋ\M
��������ƀƶ�v��U��	.��)�/��G�~dx��[����g��}5��`�����\�������vd�!:*��t���^
�i���v�u��£E�^�ROGNxܗ�7�'���P�V�Z�$0���U-��=4e�»�יsYa4�#��׵K c|�N�B�-F��|����Ӷ%���+0]o.�ik��*�}9�W��;@3r�O*��ϳ]7<3�'����}ȭ�i��~���Je}���c�d9^�G���MyR��G�;4ÉFIM�|��'־�0-\tƖ� ��n�
}P�Hu�L�Q�Qp�|�'�R9���^��@^�~����v� G��6���؁�x������˹�N��դo����&�7~�ar6/��6_�tzat�ߵ@QX~��H�6�����ql�+�?�?|�"!�y���ڬ�!���hA����x��~i(���Ùo Ǧ��}�V�����2ʒ0�Wf3��MD-��p������G���A��3�e*�E3�Q"�!��T�_N�߽����.�i�)3�7�d��3n����NrKwg�;2V52��|<�z�Cwwb[���(�W�5?Ӹ����Ӭ���h���a)/s�dȅ�ٗ'��� R�z�S6߯��!��Lxݣ�r3C�j�3^�(tf�X����V��G����|�o��d�����>O�I{X^�>�:�[����KPt��"��O��
����$��|>�Y_�c�!͆;d����ns���h�d����=wG롯�e6�t+x�����2�� vs|��^�k�@ l4���c
Ω��`����Ӽ�n�]�I�iAL@�+�sqIۯn)(���I��vI~M9�i�׺�v'܅6�JGoEՐ^��?�S����~�-��9�� t|z���z(�Ѻ"-㛀��
���ɹ+V/�z^��-w4V�%YlY'�3,���d�kt��d!A�Byl�Z}���}���!�p^��>qRf~�"�G�)&g`��<���W1c����P��c}cgP���?&��E>�KC��/��J�mK�F1�r:�_�|�(�(���Ҩ��NK���������k�z/�v�2v%��XO��(��wl.��ZKۣ����n� �g��[JpK��A&�Q|-?�u��?��ۊ@5�����h'ߔ�ȏ�;��5�5�c(�.C/,G���2B�Skz� Nl��J���I�Ne�WP5����@��v�S�|�1�\"S�
ǳ3-,��1�
 ��(.��S;���QD��7�#��ǥ�O�o�������F u#!����U,ܧ�������CE?7�� ��'2�e`?=L�;Ȇ�"��+��E��8�dX+t>��%�0F��
�p��I�?b��Nϧ�u�3�L��c8U�p������K��v    ��ȸ�h�ϦݶB:�b��fzE��1LKY�[�F��%�a��^��~cN��Ĥ���NV�vE4�VZ���L�xP�4F�*40�zO"w��&#h�j��=$9wh2�����σȒ��i����X*�B�3K�z�Ͱ��o��F+�w��Uƀv�a�0`X���U�nt��xf�sO����n���#�:2����N����:C�hg�9���eh��A��W���7=�;�7�mJ&��=�}��R"�<��I�жTȲ/(������a�a /�}c�8/�M�K�+��af=T��+#��t��@�qkc)�3�'��<�y�8�������C����01��E��}� |�=��(�V�>/M����ԕkW9{7����B\�:+'�U�lna��Q�4�!�8sx��[�ص����u������H܄N���k�T��<Sx���o|�o&��Up�-�v֐kʆ,=�i�q�߱z��ҩ�-ۙ�3���ygK8���I=�x�g� tc3�S ��߇����,�X�	��|�D�O�G�$�I�z���;\�G���(���ޓnd�ܟ�[S�i���y,�)\�t��(�	��L�sj{N�?f/�иT��8�
l=�:k��x]�i?A��i�U��u�nŪ����?:u���ۀA�s��F�U��dS��w�T�z���0�~�
eܾtfx�ւ��-����D�e�lڷ���Z��z5'U6�pއyҮ��]�|^4��L�����]��
`VwQ8���s�bEs������=�Lg��(��
ͷ<�V*13H^F����{R�zc�*��W���46�1�t��W�L�w(.���'l��rž�^ﺖ����M���`�I�ٍ.�Yo�.)�[l��:�:���i�Ƒ�"��������݃
�4O���j�=��?��Lߍ��������-h��:G/ŝ�i�VU��r��~�P�y+�E:C6C-�:I�p~�_���3��]�ܚN(m�fB"�ٞ%jP��Ym�b�ʯ�}��=mF����3)�Һ�NE�/BE���\,F�y�ԃ��|�+��롭�D0�ǻ�����2�ǥ��<xkp�s���)�R���Uw�z+S��g�>�R�Xִt����a<l��P�0;��ѻ7o`
��L���dM����_����yY3���|��5�sxr���V�gن1�+��P��"gK��
?Wn�] `���i�Dh�� �Ys%c�GM�!�01���.�i��($f��[�>���}���^kB��1X)[u����p&�����Z��qιJKQ>h�s��5z����^�o��f�W_��z1i�/N�wu�Q+{�o�R2�pJC>2��CX���]���O��Hl�{�� �����4u�	�/.�cA[ji��_Е� e��
��N�fgN[���;��v��]��<{���p6!������ș-�p�,�nf4��Q,�e����H�~x�r��F7dF�n&AxN_�=����A��z�]Q�K�~�"�Y��è&�҅�7��:�㉎��ր�GW�&y�]��1�� �"e�E��\������=��R�O?}�h�ᜰ������2qk��X��ϒIQ(n �:���lH��)\3��M��-��=�t+�7\���/!��\�L�O"�)L��rǭ�	�Ʉ�[�a��ԁ���Q�"0Z�^�#m��b�3_$į����ݳ�i�cW�B���w%S�k}P�bF!��`��y~Ut^����E��/\ ?�������g@�Qk^��o��^Kf���x�Ϛw4G��Zي�[{�e�
��99k�����re0�R՝��
ڍN��ʻN��O�\�
�:�ҝ݀���:
_͝	��-lى 
���,͞�b�H
x�MIy��3p[^bx3Ŧ���l2�Z���u�d^���b4�E�Z��4Oӱ~��/�M�C�k���oˑ3l��/'@��<'}�b�=k1��Y�����_)����{\���	����kLV�z"���	���A%S����l^a�%�C��.��<͗�Zr���mx���L��A͝ay�\i�/������΍3@X�X
�g�Mq0@�;���pW|��wQu��hCw���)H�����\H%�:����N�/+�����,�h;��|Լ�m������;�d�X��;��i۠�+��"�Lzc��Y�u �"J�Aѯ��B�e�_F��o�Ú1���V�����^% �<���w�3��W� 3��ǵL��ƞ��n�#���&�bG-�:�������W�CH��ɺޟՓ�G�J,Pѷ��D��Pv�lR(���Xv��*a)8O���졡~G��R4��w�E�0JO0���!��=�.�E־���N�S��P ϲ�v�y�Ux虚�OLd7�#]k�v����q)�*���`�q�����D�a���jZ�VX��-"����}��[�e�a&�����N:.m¼�CH��ƑܾZ�|o}�n�����9�増�מ�3l�/��ƨ�fVX�i$�ﰽ��Gq���ֿ�f7��G�N0,%e!n��Xw�t��nWp��X.b�='�����i�h=G�E=�H��p�
�4{�y"h1���0�����̯��ō��{�܉~�0��z�Q;��V� �4����2U]�Z_���]p,�c��.89�G��2�-gK��@꿇��O�#�肤0b� $�ef��Kɰ��x�-vm�L�Y���$$�.KldXp�_��U�8��D��gw����f��
[�Šh��b/}�\K���b�1AVܛu3ǃ���Y���K� "�z�ww���j�ޗ6��ctN�n�=��e���G�&ݹ���!�<���b�i��Tn�N�2�g�8��u��uA#A�$� �
�C��X$����	�~9̄V���K�J$_�n�<��e~o�T��M����7��E�2&}��GdENs�6Ɲ��7ѩ��˃�{ʠ2xx�_�r�>��dBH�����ڌ�	�p������?�W�����
P�h�"��dB�&���V����-��-��I��R��C�&�
�jL�zp	������4[(:W8P�-ҏ$�ƾn-�y[g�Fn���nU�7Bq,���*`�Q-��A�y�_���o��»X8Q�y}�%��=���z�y>��IU�l�X'g-d�OQt�9�=�H��+��1K�52p_��ZϿ{X��c˂í�G��T��m*��H��'���]o^	͸}�\ ��)IKTBc��N[�I�ȥ| ���~�0�*�{8��=��5-����9<:a��ޏQ����0|��򳑺瀪ͥ7�F�;֣5���f�fԏ��ǝ�`Вw$2����|�k(-V/��s|m��$��}-<��^DE� `O�<*I�� �!�'s�]�K,&�����8I洓1]����6SO���j4}��/x�Ȼܙ���ÒT�ڍ-ѓ�9�R�.�~]�X�>���o��|��Nh��@�1�WM撉�4�����ƅa
Zü�p��Q�9)�V�˚�a�Q;���[�����6�ɨ�P�y��B��>�B@(s�i��qs--�E϶��˝r���sS(� Y���"���z�4��
W�	Ì��>���k9E���A[7�������G9/d�kྉ�a��ն���ſ(���й,w���s�h��K�b�z�=�N̊���EZ�ɓo�1?:�.�MY �%��R�~nB3�ղ�:�+,�Ó@ʧGnC��1�_s�������>��ٞ�����X�`��;�P	�� ��E�c��w@�2@��~Mq����c�o �h�r��Ŕ�`�R"N��6v]E����ʴ^"H�]I���=*#�N�m9�_#9���q�z�~���pA���}�Ť�U=�nU�C���2x�� ��)�ɏh.h��L���S����Jr2��5�G�����-�1������[�+�u���F�׶*V`; .;#���<����:Z)[�#����x�r]ɾ&[`����    ���V�3����i@�]2�sێ;�H����|���}V���\��o�6�N�vU^��/
���JM�˞f��{ׯ��׾�;p���7�6�k��ޟ�.�¹t��tSX��	��8@ǀ\8`ͱ>�55t��u���<n�� o_O� ��Ne��ҽS�P�+egMf�� �W�̾~}#;����( �itǳQ����a��&�O�(��ߺ�fF4���	��
��n�V�W[#�8}����Ӧ���\�8W��8m��*�t�4��h�"q�j,S�STh�� ��AЂښ�c�V��lҺ�����α-��5�S���',Q��m8�����`���C�h��t݀�ɪ����Y�������&��P��}�B�Q���-nA6����c�"�r����<f�&��(����W��eX���y�PB4|EY�\��GG��}�����,���l&!�70�d�w�&
�����d��KZ�[Q�2� @���~4��鯼9���ȏ̀�M�S?���J�������1!��	�=��[^��/�H��jr�iC�a�D3��i��ޅ+-��K�9>(<V��Q�j�y՞,:^c=�O�a9�h�W�a�Gtg��X��oC?�m�Y>j�C�XZJ��ȉ�A��aE�����f�ط0,'5�{��2���a}��{�pɘ%�Q�U7�_�Ds��������e�U�!V�ږ�ƒF	$�\�Y���a98:�)=Q\���pXa�3�����f�&S�K�'�2�(��af�+:E=���#��k�C���A��%�_v�
fP%f+h�K�Gs�7D�̭��~�>�R���w��6�M������P����H��8L�x'Y��c��L]q��W6o�"�×V$�V�z������ڟ��g$�8����|���Q��qx�:��I�R� �a �Mq�KsN����cU���a90P�_�;qc��霛4C�:*|�WC�/�;�M�o&�G����Io�(�o�O�O{B�Q��J�NK�:�/J�:��_t�e��W��C�om�4?w�6ϖ��:B߲��қ�^�^tX��?�?;�t��4����K�
�!~����L�D��L4����Cׂp���	��Y���t����$ˑ����"�9*;į���P߻�).�����B8<��Sw͸M*nM�����p��A���	�#+C8,o���evי�E��U~�!g�~�rP:�t��Zc���ْ6��r|�﷖��վ���� �wi�Fn�a�޷N/�c�X�{�WJ�'�Ȇa���Xg��z	iu�鱡O�|k���\�Y��k^�e�ˢb���1��CsPZ�,�p�T��|2�.o���7����,%O����}ˢf#������B��W�sq�
�ת���?|�B a���,9�Z���-Ӎy���a���/��m�~s'�*t�-���_:��s-��}�c�D�y�p3ư^r>GރN�?�m?��뵯V��uh�(��� :���*��yk��
��M��)G�=��8sƵ��!�t�R���j���&k�^���!��Ջ���g��(� ���y�����SJR}@�{�n4�v���|�,t��?�Ɇ?�ȵ�l�+�i�O��R�Zz3�d��.�'n�U�F�p���7r�?�	"��K��}.T�j��u�� �=���r�oSzpH�# ��Z��CQ���ѢM��
��נ)0GS��4����w�o���jԹ���哕�C����3�_��������Je�����Ms��Ť7�G�I�~��mX޶"����~��	��M+��6Wuv
��
�6���2j�Ø:U��!�I �pS����Xt��W��s�z�`��L7f߽n]r�W˳�H�u8�R�&�{�
�c	&�������ٖ���dç�xP�vgzX9՜�H ��n�, d�O��v�(?-�ٰb1Xe�	�aO������I����W�20b��!{����O{�'���4�qh*|v;=�T�>�S6X��#l����5��g>!�:)���Ǎ�r
�B��!���up\��r��ǑeT��,Y�@K�!>��ѣ�ֶ��!�F�:��Ɍ����g�Ef�ɊY| ��ʒ�o�*��὚bνiTmQC�I���D�&<�ޯN��Q�̿ܛ�!�m�Q�p�1(K�Jtdo����B��Xǳ����������^�|5"����`w�����`1m'�߰���}�~?����j������{������+"�Y!��'���>���g��x1��B�K��JNp.�Di�M^���wb�I���d:�@	Gwҁ[()��Ga9����u*���x�nXY���v�/<����D~�Q98�Bu=?N`^��zƓ|c<RQm��}Z�_��|Ý��5,����X+�{+�hwP��Ϭ((�r�I~�Ը82zr�;������ֶ�d��|���:��q��*�ÐA����KBΧ�G_��/���DY�N��%�%W�ˢ��3����������KE*;C8�jco�vt4=1}����2���k�L �U.���s�k�o��R~?�:m�|�5_�F������s���Gn�B8�wL��/����Ty�d�Ӕ�ڛ�W'VN}u��oΚ`e�qmy����_�U�Uu^�4�B6ܤ+ڼ��{/:�D�����C���'!�z,wX����:����۬���a%y�F�0M�=�Z�ؕ�}�ۅ����j����ټ_����G�Ⱥ��;���ݺ*-�PS)Ikl���U��@=�ar��7���{�><���FB���U��Y:��F���cܣ���Z�牵Ke�C�Vvs��e�7:�S>JS����V��ђ��aw�7��8-S	=�a�x�W��zE�a�Q�������Sn��A�$9(d2��
�R+�
��M�P=�r���B)��7�K�a��Z"s�r�5�������ژ��Z�u�d�z4Cو
җu�P~�Mp	��t&��Bg��h��N�l%�ǓTYE�W���_\�p���x^�3��姽~B$��.�4�Ľ�Fm������־bENH0Er�ʹ=��~�3S��L0Y  /���d��y�ٿq��	���ari��	;���@B���HO�t'u�T��^���L��*���_צ
��d���
�t�nh _����@�u[�/��O,U�/���n�|�e��&�П�v�s�-{��2
[ϋ\$��h簦[뾨�� ������?�"��t��^<�+SO��a'ґ���@T�9|򪯳�����So�EͲ�|~o������G��?a����m�L���b�$}�G-�	��u�$�7r������>C�
r�+��'�P�M^H�H�5��m�u2"�f��H!����O����_w��j��BǪ���rs�)�_P�F���=��!�~=4�r AC'�V?(���ꎿ�!\��g��Ȁebh�o�*����g�tx�a@ز���y�l�5��v|��`�M�γ5�u�H�%� ^[ǾB���5O��R 0;��{}��ئ�	"���a�&�w�7�$qk�����+�ڗ߃�Pԙ�56�K��� F���>��T��9y6
F�~�q���=�;۟7����S��F�q����o�״���
���a�ROC� E��7�t�����!��ǿ��Ƞ��\��aXl���/_�����̷b���᳞�h��0�x���A�7�P����mEx��5�p��/M'���� r8���N=n{KNaV�%�7o)y���wi�A�e֢~B�ԢI�F 1�`��a𒯅�2]���d� ˸�]�\�6�S�tX�V�[~� +V�%��7�QMAhk��t��Q���	qp��d��R~t���?�@�����4��\�;j(*ɐRۦ�ވ|>7�$�<�0����>�g&S2��١v�K#*�ٓ�hD)Գ���٣������'}���ib�����C�]wЛ�F��RW(�R����U�|�9H^�    ȱ�;�x�w�6�L�eC���
+�#{�F7���~.D���ȝA<|'�|	��E�Øh�p��|�������NWC=����%\V����;�=��f��(��Ҷ�0��!���>4�*�9�y��Ov㸩�6�	�Ê��i'y�'��-OE�Sw�ml|��������򻘮�O��ʓ��	���B�ԇ� =�>'�/����:������/������r�����ֺO�����h��D��C>,?x������/�A���AS�S��P�5��k���n�,M? K����HǗ�N���);�a�i��a{B=�mO�0��t,�Î |A�[0�%:�6���%�;z�ۥ��AdG3�h�W��<�wF�Bs�v��2�+g����|-p���3���6�p�N���~�j�����e�[�ʯe���78�u��0IP�S�>�����<�F�7�<g*��Q&�����a
)�l���wUp��<��	�����؏�F>�\灔6�3�Ã(��m`v�B���S%t�gwG)�|��4
ȳ��λ�9b��(�~#<p���R�_���Ѿ����R4KD�_�ݰ��oȇ����V���u�f�����R�����޾�Kgԅ�Ot@6�{���}�l�Zm����0G
p>t�W�c-94���B7����r2�tǗeTFtM9"�i���+4K�!X����v��vz?��9���;�-n�<����}:��t��Nm|Hc�b!�")�0�>vq�9�e7�y���F���������]�~�ֽ�5C8�?��%���ۉ�h�6��F���OO��aN�*�=�n����g�-D��M���'�X�w5у\&��4A�t�Ûu���t�mX6�j_����a��ݛ%�T��x۫#��ᒄS�$*?(��	�e؆��R�gsx؆e�n�o��qE<��3��+�$�x��ǝ��6,��]��u��-w�����u����Q^�:x�{��ޖl�:�m8-�D�D�2����(� 㹣��[�6�7ĶY���نK'�7��a������;w��؎jY�u�wMv��|C��4�k�>��c�U�+�#*�w`����F2*3�84��
ث@��2��Sl��|@�������kO|2Fe$D}Ԑ3�e_�5ݣ���^���\A�a�0�sϚVS/{6��\�)
��ʌA#�>��ɭ����댖O�m�	��̮��ޫΉ���ˠ�Ȩ#��m��GC+a���cC7���mQ��ˠ\�\W���H����r��������J��5n��7�!��$5���G�Y`.�.N�<E�D d�zZ���k���5,��N����d��CT��;:R!�=���]�pgȆu�хx�8�F3JE��~�� n[����<E�( q�u�i�@�w�Ԯտ��6�  �5\O%���xܿ��i��>�n!GJ�᭰����m5��������c��^�g�E$��=��|d��3�QYJ؆_����X�7�&l��E޳_zR���h��f
�9(�3X��R��W��_�S��W$�Bu����}:u��9|3����K�����D�p�f��{�������g��Yr����92�&��Ӄ���7����� A���W�4  Op��d�j�`3�.]A ��Y����G����+K�=���W76���ܚ���6k�/RM���qx=�+B5�H�:�"&�4#G���@o_!*K�1:CQ��e�{_��B."Ey�QF}����o��.s�3��t�RY�`X����r}���	�F;7�_���,��U~.Ze̹�z��d^���xߛ
��qP18O� V�3"��=�~k� K��d��Ƅ�ɍ�7�ŸSE��3șx�b*W�z��M�����!'�Q��Q,�sxӨZ�������Nph�#H,v���#��D���ř:s�mA�Ȼ�h[�@
�7���$�D,Ҹ�a�/I&�]P"?�����7s��1� %ˤ ��~:��ū�� ��٨�A:��%��_�r�oҁݕl�����'��:d�G[�ag�a��N�]�.�B9[�������˹9�h�@,���@�9���/g$y��j
ia�._�Y�S����`�˻A n"�bw����+��;$�y��f��'�@�Fe��	+{��7[}�_��uV��\A ��4�ꍓ�3�C�r�H�lu}�E�� W��,�9��w ����wI�E�n�+s?�@��܊x��	���df��Ҕ8�07{]���h�1>o��ڏr�F�ٝ�K��j�`�pv�ڶ����*����w8+ȏs>�O>�yiџ�8����C+��P�[���o~U{��(�����h}��mB:|��@�N���ѧ=��m����{s �2��U�w>|Fx���Sk����4!����O��&�����BL뾄���}�d��D�o�wx+>���d�{�;�:��,�V(��X�w���kr:ܨ9H��� �,�����S�G!e?������	���%	az�tx�cY��(3
��6�^ȹ���Fp�!�k>���wus���|tj�鍫S ݰ'Ơ�|�~AA��{�7p��"M���+��� La2�&��m\�����;�eѮ�Ȱ8�e<ƚ�\�d�r�u/�C�15h������<�Ѳ�>��3g*�﬷vP�;���F��NOa���)���rjۊ��3m+��i�wᘧ�3j�Orзūd�Za�|�' ύa������[�5�i�p� 8�}�LS���]S-��Y�I���!���ڍs6��
���7�	=�o��ɾ���.Zݤ��:��/N�i=�U�ph���@;|)��:.�q���@���x�w��|�3Jڀ��g_�ո��QS�-<�a�G�όn���'a빱��O'�>wu
�{5|�[�<r~�k�`)���:Z��|�N�/�o�AN�>��ܞ���I����:�hզJJ�z<r��+��Вv��&��:�^ߌf+�ŧUʻ�p���|�>���`R,R#���s-!�S�E�O���|{���1��a�w%WU�������jWKChpD�$2�Ȳ~h����۰�C�*���P��C���:^ޱ�Yw2$�j����X�(��o����|���\
6i&2i$a���լ�o����-o�`u+X�ɖ�i9�F߱e�=�y�	����;LtVä��ౙ��4\t@5�чo(_�jr�����@7L����4�J�0���E$��؆���Д�� ���lD��̠Pz�
ŧVWiǖ'h$
lÏ�����W$a���!��{qd��
��o��M'�k��G�\.!��S���%�#�9T+j��K#_	,���>Ɨ���6𰯘iTB�T8�g���]������>���k;�@ۘ��;ww���>���B��]E��(�lF3�v������9 �W�{h�K3�����u~��ďA�I�}��ϔ�~(B�H�b�==9��L.5�r$�%������6݀�攤W-U���bF���
�2����k��HSV0r��70���]I�Dc'�_��/?7���sbX�l�x��l�~	���T��jB��%%���O.��a�)�r�c��L��1��^����^y��_�Y�����޶��.F	_��:�V�4|��C�JS�b��������p�Qh���*o:��|1������@��a��訋����3�n$/4�X%�6�)���1���uy�ӛ�ČF��:�;�!�v�u]�j���a@Ŕ��<�s�DCU�r���f�ۚfl3����C���N��}�*Z[��mS|}��5�pc!���ÝI/ؤ��e!�������f<}޹n��L�[H;lͽ3]���qu�d�fЀ�Wf������ e�?��څ{_$8��s��T�2�dB�Q�`r*���?�[�r�<��$o�u�C�̪ښ?�Ew
9,�}��Z�o���F��6%N�Ψ���:�/��t8č�����	u/ny3:<�D�5�B���ۙ�|�e     
�z��[��@@<���\Η�`+G	4wQ�Zy���+4��{jj�]�3^k��N�3�/n|�u}�Ƚ��ѴA6G�W��B�[��C���#��"Qx-��W����9ʵ��H��R}*
qi.��7^�}�Z����w�/�y@.VF��xl-���|��ѹw�h	�wx8�� C�޻D4�g����䤵��y~U��O�t���Ne����?{��sU�u��$r\�o�:ij)9�A`����J�T��$�N��vq�P�?�e�h�)5
dg��/Օ�g�Z�8�ex.��w�0��")�>���٬��#�؍������k~��:k	��-�YM��R7��D�,O����3O��竸��hj�e�t�I����Ñc^�56���A[�ѲNd��L�Uh��t�8׷.���Xxw%�Ί:��5���ī-6S'��kY5��P#��:mk��S�����KGP���T���0��j~YD�
��j!4��0�hb7f��Z�{V�Uo�@�f���~�"�)�R�5�	�K	󍳡ό���@?�e�N�G���}�	GԀ��������4#+vR$���K��P:�֥��0z0�(�)
����b -���h�<n[�k&�����"ߔ�Q��mX�I�t��~�ao^�g#�������+�1��8����b�^�u���5@aӠ8����?�@7����*l����i�?�6�f��t�^�׷l%���2K�V�﫹�o7�g���=[�����a0C���w���l[[���oQ���=nS
�B:�mP��Q���,`]G~y� ���B�^M���-���c)&�"�np����C��ft6zX��l�+Tm�?0�������U�A伿LH�4sͥj�������D߾Zᡎ�fo��W��|�+�w���+�ظҿ�F����%���r-r���T=�
�v͊&���6���k&��	�o"�"
������-��p�l�j�_!W.gp�U���
�R�p��0�m�Tx<}�~ש z����i/w��[��%Fa�
�
�f��p���@	2,(���x��s�oN�f��]A�ͫ#�=X����/����3��;�R�}YM�5�s�\1���5�~�EY���E ��R=?�C�K�[�@�߉�
ό[��8�k����k��YY��I_�C��v��]5c}!;!?��Ǭ��8c�nݬ2�uА�Of�������F��s�(�!��S�� G�=Z��;���_;u���=�n����$\��L��V`��ڶ89�U䈥��˹~��Z�/{ �5�*D��Э��	���L%�����j��6ٙA�5@�ii~�/r��L�5g���Lz=�㜳�km�҇�C��Ⴙ�1��_c\����}�J?���Mt���X�6�����yiK���t�����߿v�B�y(���UpBI]3z+�@��:}�ʁ�U>��Z��y�Π�L�3���:ۖ��Q��ʧ���k�����Q(Ш��l��z)"�9�r��@�-�g��R�h]�]:�c��G���KvY�Ɨm���jn9�!a����tD����������4�.[C񒂑O���{�Z_$m������Sӈ��O$@�<W��,t��7� �a��A�{�XN�t��	���\�*i>I�7�'%��=k8@��j5��~CZ\Z|�n�Yz�U>96��z��:��&o!/��;��(�T��S��!HVpޡ(�����u3��]>�Ѯ��j�%�ƭ�E�;��y<�4��:T�X���>��|R|G�5�P<\ ��Ȣ�3:��b��v�`�ad�@4V�7���ɡ\!�R $��9�e���"ѪT���b�6z9��/9�@8��!�S�.y�y�%E a��ސV\��kTf`�$��@��n�Êb����_qŽ�߯�����x�A�Z}B1��=���!� @+�rD�&��#�RF��M�4n uA[S Y�d���������˹�i��ȧ�7<����e�d^u���n�H�>�=*��%�t���.����?0�j>�0���=�]\�ߋ�@g��>��XH&@�X���ӹ�H�)��ף��W��|��tR��m��4�G��q��yC9\���L^����B� o�j5���O#gDgZZ6d<�N�G�)�Ǚ~��`�RO��l�WsM�F\ǂ�	]Ϩ�_m�������E��s=�@����:�B꼊�EV(��C���6�[������"y�Kk� ���B��)V��M�,w��[�%nKP0J�b�4 ����[!�N'�4�;գ�uft�ƛ�M����{��̦��X�ڏ=��sc�a�c	�]��:��s}v{{*��\y���X�j�����q-��K�2/GĆq��F���6��oC�v�ݣr �2G���ּ9�|�]e�8���p,<�9}j��F*:@��5t.���G?�ߌ" _B>�X����m�zsn��U�Q.��?8}���>�������@�(���)as�E]��ބYr���߼Ǵ��箂STH�7Ihgv�gC��f9q����,�˷�	)��G�IaeVJ%o���w҄й�@~��(>-���T0�L�У��8�����������,��ޠj�����W�n�=Թ��.2=�/u@*��@iV�	F8�O�@����$�B*������܏N�<�~
�t+|��_�:��d���|�Xx5��Ǔl�^��`�ӪK2���|X5�j�k����	w���D�|o-�.c�ʊ�OT��Gg���B��w���䦿�?�Wߐ���M���lX���L���m���ڈ������JC��I���>em�>_y���g�a��ˬ��,�(�ݾg<����q����N���]�A�Q��_�����F;����HY�j��s}�蜊�/�O����~_ќ��Ak���wo�l˳��>�`��)�	����������S��&?�"�m��ܯS߷��w����3�t�ފǧ+<�-m��՟%�{�	��+�(���,FM<��+��5;P�'O�\ur���2X m i�cX#Gv�0�z�q�@r��L�h�h�������!���g���ӑ�a�[�2c�L=W��8n���Q�7���(�W��~/���&nD�6AP�;����"��|pH��J��q� 5����&�~�|��j�x�7�B�\�
↜��\i������ӝ�v?F��,���]�S�jԵ�Nv
���gT?��I����e�r��WE�0F��KG�¥�O��Dc��h�s��Q�ِkL��[ ���tz����o��
}�ھê���b��C��?S�A|�>	:��}A��{��f��E�����q1�p"���[����3ͷM����!�p��d����K���G��!��ǖ?s�+�&!i@b�k_hG_t4���7��Z���"�ͺ0_�f�N3~�6���uk�W����.��oSa�ꮲ� T�(B/�幞����6�c�ä,�8j�{���]B?q���V��Wc13G`�!<�m"GӋ�����+zo��Ǩ <��u�����O�x�9���Lx�f�)!ѼN-��Y���4�Z��Hb0�l�{�J��+�Uq0�m�|���,�\L/�@���4���Ƴme�����<�ed8i 9����u���\qB�q�bH��y�;���z��f��_yL���o b|����!V~M�\��Q���@]>\c�'G����F1	�P�o�4DX��QH�_;B�/dߙj�4�=�c:��T\����/��ie�b��"��U���&��A͹���[�X���p�h��q����zUB����"R�h����_��O�,��gS�&��W�H2kU"��P����*����B����}��}��j��OD��m�F%62�$����Z�Cg�s25�%t��2a�����1Q�ֶ�q�=�ôE��Y��������O(�A�G��mhpF�x�܎��7��z�)�    	���O�n
?�?9�<��uhQx��/��1��)�&%욖�à���*Gwx���^rk�����R��ʺl�/�\?w|����@�0������M� �������a�������O���b��	�c�=�Whӱ�-*.CB;� � ��7�^	�A�\ϊ�?E��9�ƨ\���K.��!�9a�i�/�k��~�i�lpX�lKڜ��^���͉S�n�I]�1yF��_������T������fa=��}����5#���z��` fa'�����5A��M��9�s�k���}@þ�f�b ����|5�.5D͐��U�NH:e�h�-��s��v�ҳ��<��i���?q)��D�D�ts�H�Z�(j��@gs��Q���}v�}�]1���x�}!>H���J��/07���~���yzEiK���]�7F^��/����_�~���,��K��m��)�;&lpI�c��?�Z�CC������ ���>��&"~o�G��z�{��#rg������P�½W��ړ���$��T҇����)p�2W�O6m���C#���q��������T�#���w�Z�P;�xA���,?���sj̈́{^
���E�8ug븐�+۩���̣�ԶѢ�[h�*������=�F.��=�G�y�W�sao�Sw��_O�G7��7����67y\}�%
��:~�N�l�(r94�]�)� :���V�VXVF;V|V�4#e�����ΫF�$�� Bq]�a�,�q��#�|"b���S�	Y'�f���<��5�"��X�]�L�� +�0��|ڛ�	��8!F���	���r�`j0[����+�3���3��0��5�g�0U�7�����f���Wp�W��M�: ��HA+<u����؞�-A+������w瓟B.��;V4��aAA�Z]���kᇚ-����}���]P�f;(��x3w]��˔C��U7k��}�n��\"�si�SM�7|����W2|�Ü��SF�\�����^�n<�Qx&�Ά�_���� B�8;�y���w��A|�k*�Җ��2��W�'��.���]hLY8A���C�:Ҟ�T@��U���dH��R=��%�0
wy�0�Rʏ�0�q`�vD�H�QXG��^X�M��sS���=�}�1��W��o�7�x�W$;�/�58�A��e^m�o���I���˼�Ņ6�+�� B����o�2��7���²Od��y2J߿�<|�r��Tz�А4��~�\`{ވ �>'��-�-M�Ct�D�4[ķ��Q�l
�[�{�K>�'�1��Ꙭ<���c#�]"��OX�q/Z��V>��+�	W��x�9#���rg��+�\�w5�"���>�"�:e#!�i�',�G�7� ��xX�����e��^��V8���XB�e��(��f�O"���E�.�j��~�~���$�a������;�����H�)�% ���	�
�A�Ә^��&PG���y_�7�D4��N�U�	M"]�Ԕ�%M9��e�Ox?(�,��-f�0���N�J4����s�t���v7�|�Q�OQtN�b�w�Ox\
�e7a.J�5/&�=$�3�D�WӢֻ|W���1���i_� �K| JX������ņ�P�����"�*fk+&��'��1fv��p�կ�+[h�j�+g��޶��:�߂����i���}�&pzB���(|�WǪvL�c�Q7�Pi)4p)ɷ��Y�m�}p�ُ�_X[�%r;F�O8k���fF���;���o�G�p�hDH&�@7t��6��C�=����Ew�Oxh�^��Mi�Ă/�F�esp�򻘂�^�U��>q�!��toQ�/O�Y(E��T��O��
a�����',1�&;[C�A��S�������]D/���A��'[Ľ��V�*ϰ�_j6�w�,ސ�'�a~Z�.Z�t�����H�Ёu򝟿�e!{�rR�@�gA<"���vp	w�D�����p{Z�0������]��s)P/0	�3/�!�SO�c�E��)	\/�S���3��W�q+���H�$�$<���o-.�vXCJZ�v=�<M���WL,�m�X��۳�N�p�;2�1��u`������*�\�,)�_�D�+l��x�{,��I���KQ(��_�t|c�RX�5E����F�t�3�[�~����R��v��O'3�(��Y��yl�pm����jH�;�� j��P��]µ�Z��^)��,��������..P	w$���%|~�=�ZS���S�P	?�R)���"��1�f#QG�G�˔���WV�ۈt�G��m�>�fr��=���fp�&�X�d1�i#�9�ȃ�*�=\�"9�:��HpB1j��[�%l.�������t!��3h\ʣC��\dOl������W#o��j�������=l�w8YZ�F�*ap�����	���à`&��]I��@L�Q��'/��.��dF�<�~z���	�v�N6�k�F�4-�ՠv3��eXg��䨿PU���`�]ԁ�Q��e4�������;Tf��x�F�	����o�X��	�� ��n�a���#|M7 a=A��MrG���|xJÞL�X .dˢ�G�P���gmK��|�/6n/�5��%���|����e�,�aźCΪQ��aH��D6�m�B8#�DC"-��ĆBXo��z;��7��P+b|�ӆ�&��M�!_��l]k|�]��e"h��$dQ��αu��7��hr$;���CX���ʂ��$�s�q�����|r1��p+��=�WT;ٳ�]�%�hv|"T�D8��S\�*K���+Z��h9b���n�y����oe>��͓��6�er���".����BU�4S�e��@�7��p7���d���S�M�$��K|��t0���� Ta47��
�} ���#�-d�xJFP�Z��Y[i*pq���F"Y~�C��}x<K5 A����w�G73­���%��$�ڵ]��#�2�q)>]�'Z����F�yl0�?ph�.?���������Іx�gF=����E{<��+�6h�s[��T�k�29,�Kh�M���Mr �%���z�̓E��5����h+�/4��ѷ�^J�� ��Z���&,g�^�M�a��R�E����?�������LF̭��ɯܷyf�q��HXC�ٝ������^&Ûr�2�GF�:�[���%<�M���$�������{�[�'��J/�R�/�&9֋1G�*a�	!�h�2u��_��Z�n�(\�s��K�0
��)�s���)v$�Y媠�u۩4�p��G����G���ħ��69L��¯��x??�7�Z��+_e��cog�p<S!�;�Eg�Iݩ��՞!�0��ʛ���붚zІ@"<5;!�N��oZ)e�&���ۜx4i���B0���w�g�\f�@!�I�����Z��Z:���p�ҐKt�s�|\3�BxR�-T��~�9(���ٹ���.8�5���G�Af��U�!��P�.Pː��]0��A6��^5�x|�
wlة?�U��F9+C���-@M���סsB���Be׾�U�8t�Dqa���7gt+��� �D")1�
��K�&Y���ֹ����i�N�E`����l.M2�:�p0����7aګ`y��V#{X��?$�3�55�?��~�F$�2I�����Aic�n0���B�����[l	S�5���P�����o��� VS�������6�0tf[���l߻�gj�6v�T�Dxlh���/��y�t+(�/���Uh��!���U�OƤ��|@"|}9�ө��CH���mN;����z�I����	E�F�����	��-7�$4�}�" �(�t��фʻ�$��i�W�2<¨h��|}�
�+�h;�|�
I�=�p^
-�Yuq�ɰ�פx(�Te���P���h���@�4�6�/7�    G~���҂
�_�)��e�٪a8�!���ENu0\x��3��#�_�:<�g��І7��"�W���s�ܿ[�ҖP`�J(ey�&��CR�C��_4��ѯ�`p;�zǁ���S�ړ7�<E��(��?�+��$\��\��%��&�6j�V$�����������;�żҵ����5��9�6f�PF&��QK^.�1�qr�\	8,\�m�����Jx><���ԈyF|���}�{nb��1��g��X]�&�kת���Rz�*�ޠ�'odR�'��-1�dj�C�_wL�7`c�5�+��S������7q�[�!�(�BQ:��U>��n'��ٔ�C���C�	D��ό
>�!�,˜��+?lL�Ia�4s�2YP	�!E� ��x�|��ْ'��$|�G���� ���M�:7ю؎]=�2ez_����Y�`NZ3���TWQ� ��^m㊿�,��ͼ�W:S/:]9�l��">��9�8q��K{��dXz���DJ)��/�e"����;��~����q��M7`Id�a��B�>�7�,ش��e+����H�l,f����+������=O+h�=L����RSj��ğ9g��%D|o��e���4�#���h�[��l��E#q?���������c�; ��3�Z��#Q@���`��.����(kC�\�Au|�h�b�����Qg��G����L��˹{��.MЯ%�o8�)��a����ﺟcPoGՉ◖=��g���N��&=�+���C��:�澁�����.����<8��sJ��7�n4
�C�!x�C�:��&F*J\��OH��\�	��v��,�K�ڹ:�P����+t����
��D�l��?�L�CE��v���y�r��������LAwƵ���z4�"21p��F:����_�&x���������.��2`fF�t�gus�&R�v'2�3�}��!\	�h���&Y�!�Y�Q�V�dc�Cx��Ld[��-�@!�!S:����dP�n����L@�e�����1�N�y��P�ϾI��r��;[��x�X�C~��5���д_?-{���$m�_uE�5x�'���e�m�� �didrȍ��[gt�u��>���2=�3�_`0� ҝ�v�E{?£�dr2G�EȚ?P�4�WK�!,�����a�[�J��y���m(��i���|��B��;�D'dR�k�>Z�����=G`��bQ�B |��� ��Wa�α�G�{��	wP�W��:'STK�k	��r;�b�<v�7�;r����r� �rHO�}鎧�$|�,c5���%M�$%�0�y��=�M����\P�h�����xf��lvU 9��XQ�Lշ�bc�����Z&��mgh�&73�d9J;�e"�<�Q<�9�E�/
����$f�x�Յ�G��R�z�b��yM_�O���9X��*��s�.+~N-���^^���cW.�������h�u���h	o0�r��m�#B:�<E��<]de⠀6Xal�����G���л�o]v���MCN�IǮm��	����@���fC�XX�tn�����lɪx��:�����}��)d=c?м�����"-.Z���n�q��$߮7+��}'�-p�K�}�[��מA�������A�� �������Dp_CǛ"����x�0X���i,`W=�C�"Wod7����˽֍��c~1�ªܲrZ���
���c^�z��:����C['E���=��N�g��ɺ��$��k2�P/Eg��*��ɫ�c���{hz�����0@K���,} \+?F��-;�B(tE�&d�>�E�=�o@�?n4��� 7�= ��[Ɲ*� �.Xo\/ �-�Ԭ\23o�t��΍�h؂�~��w�~İֈ"������%L�w?:!�8��L12�2=2%uCVW��U!�ז���'�� ��?����]�l���8�g��=���jՔ������fnV�`y�Y��k���q��>	���]��g�6��ǀ�۷��u5"���k�����+�����d�^�3xݛ2���2d\�~�����<T(���ZQ��O�=�C�L�R&j�LWxN�9ɕ�&l;��k{P5��?���	�9�2��+����4�U��\�*�!{��e�_�z�3�Cl�e�ϥ ���}ۉ �L�ò7en�����)*r�/�s�
ap�l+��U!n�Q��.�d^!^�~W� ��Syq�>���׻�n��~�&W����2W���Q2x���󚬥�<�Z�u��xh������W8�MF�\O��q9����DS��<܌�Q_�,��mނ�w�}WDqh��Q��P79'k�t��xEr3ɳ��ÊQ��y+3�E��w-�p����
ސH��E������2�P��|/��h�',k�ɹ�P3g�̜s2��´�SJ��[1�H�]�.�?4�7Ɣ���`���g���N'��(���,����^��������/k������Ӻ�/':�����d�M�#7������ �@T���(j�US�"i�b}���M����޽ű�8)��� Qwơ����Au΁_�^k�﹩��.u2L�~:� !�Q|�-�5R��5*��
d��}%�AY�0$�Y5MӒ�J�L0*<�x�� oL�i�/��'H���.�/�?���(wLC�K���H�������������*VE�M ?���OX2eȋ�NKa�h\�r^Z��}�A��t+`�Z)��b+T_�8��;L!���~�� �fܷY�Y~�ܬ�<��X��kg'b*��
�t��otpk/��{�<!�\����(%��+��� ���`�$����ڞ	���ß��JρF�O֮B�sK��W��ʿu��K8d8���& �ʔ����S{���|i�io�8�D��
�a���� C#�w��M]�c?Ӻ��Q/8�M�;k�����/X�����2�ԫ��1u��z�K����c��Y>������.3ǆ�����)�ؓE�౏�Gy���3�^�x?ڜޙ5�#J�|�('U����@B){w-�Q����N�kY癦��~��t� ��ˊc6:h���*������Hw�
n���c8%��6�
o0��ej^;�w���M���1~�:rF�&8]RV諰|�
�A���##]��Y,ɢ̕y���]>#ݓ��*�ɏ\Xx7(���"��]�W��lmv6���!�(����h�:
Zec���<G�ᑮU>=�
M�a0P;S�"�]����
��}�c�tt:Ql-f��>���Oxm�,j�eӽ��M�7x_�@K���](7�R'�y�fH֑��~̲�{j��=�|3�E��O9z���M���G�p�Wwg�����8��v$_-�M1Α�=ހ�3�"վR�g:z� �1
��I��ޅ4W��h��4I���gs��p�[��L�g�����	�Ň��g���~i��(��WDEf���r�����S|r��!b�Px�HK�Xy�0��F�ʻ(ĺ����i�V/�؏�Ā`M�}�fBb�R��cڃfyæ���-mO3E�3�P���l� U���ڵ��rQ5�ف���K�߱�
�-��8��8caK� ���Ԝ��-t�����-���=)�y�C�T��C���O=��e)�ozNw��0ԗ��M�wt^�$W~t7��hrN�f�V�Ed0� 5�  x�{M�v��� �̵i	��5G�H�m5�+��''G��ܫ��c�0Cbn�ŽU|����W�Q�h	��Q�ρ�Gi��7M��͋�*��O�%%B)�UJ�	Yh=�����a���d�JҞ�ؽ�{���S��83+�l�d��Jo� )�5ڂQī�"��4Y��
+^�>���o� ��ᄱ�a�:�k���'����4�!�$��T:s���Sn����W����	�s�+G��5�F��r���ql#�3i0ɀ�2��'l��v�ղE���^��:�I    ��h��c��@��o�$�Y)S����k7-���[�F�0���f6\Sަ�6//jj�ݔ�ǜ?5��.�t���9&$0ޠҩ��gi���� h�p��(6�$��?ʲ��Z�y���[��I�QF����g�n����Y�㓩������.��ii�N��`F���~�O�[m@H��;lM�����r���j��`��\o�����z����{i��y�v~|�"A�k�G'W���(��2��������>���x���`�����Z��@Ld�W&��"2��݇�+4��=ڭk�.��ݨ��-���^n�H����$� �l���ڳ�R���U�@B��NʑO�j]�&߅�ȩȀ��y�<!�i�w���p!�ܿ[��&�WS�T����{�|�7I��s��������������S�#|�@��0��4O�]�~=?����<3RZ�;�#�+��\i*�Uѡ�^��'�����S�l?���6P���WrY��%/��u��&�S_$��k�Ϭ�.ɠ��B�eVsW�+� �z�n�&�4+T �N���o��/�u+���
��$s$��H2C���
F� ����K� �P�UZM��W�*
ٰ;�o���<�Uh�S���5���<D��g�	i�!K��q��Em&~�i=�)����jZ�a_�#��{�g�x�����L��L����]��`ӻ����3��FF�Z$���4��,���,c8��3�o����| �:2^���(9}$;��Rv�`��|�������$� �˂�,�}+�פV��<��보p��tt���;�F�0�hV�ѵJi��Ê~ǴF�o0yjT�Hn�>7�lAu�(
+͢��CTx���Qp�k8�tLA,KO�6<��~F{p�"�鿭m����h�Bc7F`Z�D75?�G�S`-����_h��lmP��ըz�W+ټ� 6��T9�c�4��1�{�J����L������Z��5~�Ǚ(m�k�ʧ��p]���k:Z.�G�;�fO1�����Ι[W��ٺ;��.	�#�'(H��]�u�iL�#���Q�k*�6J��7���P�e[�BU���o��b]��K	D0�.
�ôƞ�f�����dż�*��C�����j�`�r����p�ޜoj
ͼjL����)s�h2��Zۣ�b��4�N0�i�.���\�rt4�~O��q��p�y�ue�Z������n�2���'���"H��O�rKu�/@�_�m���X��F�S�t��<�����3|��@���=X�+�5����?G��[0�M������ګ�ǹ\l;ɀGg+���<$Ms
Ptp��� ��r��4 DQ�f�;�O�^K���8o�J���B���YVUJ�{ ��hV2��f��wyi9��>ʵ�믈B9җ�����e�7҂�!Y-�R'�Y�ؽ�#��ȊO�#D��K��IC^���n__5����+��ֆi����CF�Z9 =Jz� ����@r4�2�A=�z�"T��3��M�B�ju,,x�3ͦ���L�P���)K��MX܉lgY��-r'��5ڳ���!��Q(��鶜�!���MA�����6'�Z�d���N�5�k�;wc���9�)�1
�OD� �t�*��BAȧ�	m惦����kj^L�Qo؛N��
�^��.����D١ �,�W�{��o�7={�΀̝���
W��P1�|��;�oX���&�(;�H:I���(4�y��Hi�ޚp�r�[w���մ�k̲!�7M����]�k�ⓓ�e�!�VL����g�f6�֜j����~�l�u�&�OZ��cu�eW�<n�(�B�Cq����(��Ъy���=��/�+��'
���~㥫���C�W��qC���i���rt�D��_���< �^�����@wY\��WWyd�ٲX��㳂ޤ:�s����@w7b�ʩA �!���>zI�#�0�jf�$�9m4m;'%����<��t)��WaPn[z��i����F'E�>��2JS%����W�5"�̵���w�$ �]�}�n��u�����'=t<�����(�ԡ\�<V�!�7k�<^ �̝{��UeZ�=bn{���kp�tUS�_��A���>f�Ϻ�1O���;�9X�&�����\��b2�xl��䶽k�T矨��S=�����[�}E謳H�������M]�E���j�ը!�3K�|�ȦC���j_��Qz �ɉ���ʭ5���+1�JL��+2�.��� {2���C�ŷ �&��h�P+��(V�ƽ��t�1�ׂ�Fv��m�A%R�,�i�Q�8d���u"�f/iz� A�Pݜ�b{�~v��{Kh�R�/��u���Ej^��6��#�+'a�����'���yn��z&�˨^�O~�z����m�TVdG��Hp����z��uo�
9,���>x�i\k�g�x�h�;.����DĪ���[��)�n���T69�C4��dˏ�t˴Bx��V֣�]d9Z��P�'w~Ce猤K�L�GnU����ڸ�rnT5�)����*׶>��hoP��WӲ�5�̰i���Z-ϗ���_�l�3����
����tR��V+p�ǡ�Bx�����9�H�ݓ���F����M��e�gi�<�，�^!�x�A�+�\�7��U���-.��Ϩl<���z��X��^)Dj�n�s;�&�L̰���#9�YD5�~ŻR��ஂ��"�.8Ϭ?���c/؂���s�\����͒=#Նl]뿛<ׁ��n4��/�i�=��7�s�U�)�wtRv�$�+K�0��P$��
F�:��"+jbݹP��(������񬍷�K���ە�3��ŏf���f�) ҿ�b�+��μ,man���y�k���f���b��~�ٓi�.x3���z��~<��W6I>0t��B��>6�;��<,+���mC"�X���|^2��{�D��3#Q
�Q� �`�q@�e�8,f���y|�/$�+�-*��Y�ƒ��0ޜ��+��+"5��K��;���UU5UKo�����h���H�#Z?��6��m FU~��J"Է���X	�앯 �	�T��rdh�k)�J�|mO�����IW�<�<�b��:bX[O��^�]&2p��4�v�����k�ص���1�=کd������ՈW��>���s��Eg-���+NE����_> �b��k @	��9}���:��(��>l�xì����F�҈ss���0W�}q/���Ahe��KG�	X�orO~��:,��4�V0zO���kݔ4�ئg�Ww�͋Fﻂ]��0و�G �FϦ)�_4R%W_���'\3�����f�/j3j�ސcs��Ս>��{��~uff�)d���DQ����d)9���������kH���������Ϣ]����"��0Q�'s��#��k��+O`�5��VZ����y��0,�a����㸌��sX��%�O� �����T�N@E�`��C�h��`�k�����+������4B��N�5h�dA�-�4P�T�dMjȠΉ�fՙ(S�Z��B<檽h����w%�1'��$�bT�ӝ	52V�=�Ҵ�]�М�c�;k4��^�mVi½N���u��L7�Z9�کr�y�Yrh�E/�����^��:�ߋ�W����c�XІ72
��{ jrj<�>����
.~"�~<T��u�iR	!93?�@���|���Q�����M=�������2̙?�|�� L�HFtA^p/2�?�h|�Xzqn�ay�.��MS��R�լ���礐�F���R�}�v�7F��p`�č���9�<��ï+]+�	.�X6'���`��©���eUZ@�ل�ϲ;���)6
��[ѯ֍O��_�7��ǻYÆA�8KU�*�h�;iz�d֖���tM޸L������WS�ϟli��a�����rd����;R�,�����"5���K��iM���/�T�:���mf��=�MZ�EJ�Y3+��rj���˲��~��ފK�|�ã��    �^3��zFt����ᣁo�ݴ�X�C�?���I��!i^�$3|f��ܿÝ�78�5�����;���^��)q���Fр��AW���I�Y����
sp9r�4{^cq�)X͖��)���#�8�g>��Z��D+<Z�<����Oki��HCjTV�W$��Ǵ��W�Pg�q[��
=����	��k���V7=����rp	�E�� �ۙs��=�?[����c 2�J��r�:с~~;Tnͥ7��DG�*�����=ׯu�¤%��Y�{tB1���^�4���1�ɥ3.�l�|D����\�������M�)HB��C�镅��ȍ�)(>�?����|��W������\�H�A9���4��>q�n2e�����- ��mj�ό���8ne��Q�^�p+ڙ95z�o��p?i\�#��GI���`٫��4���I�d�(Fρݒ(��᷇ᆢut>� �j��[�*��;�	��; �����G`}��-9yZS;�5J���m����J�Y����gʝ��h&��1��� ���s`{�?[_"�OBװ+�ߡ��WnO�����:�D�uqF�����H� �u�W�4h�F�ӁKuw[Y�e5ӏc�)�����V������+�C\������[��^�4r���BqR��!M�N��u; �DE�=8�w�6�}�j^3�>�|�Bw��BwW`�������O��w�'��z����]]<���? 5�ݾ����zq ���X�	��):����"}����mN��ypgɣč�T'��㠙�/+�NL-�M׆a��qs��`�B��9���sup[��g(�F����X�qw��ڡ|ةi�fןO
w�l�ޤ��3�j��t��C.,rʐw-��ܝ��e��'ګ-�q�ɸ���lm��RV���e�?�N�:`�Y�5!�ri����:o�ut_M>�(��%A����c�z������\�g�t�2��Bӕ+�7�֡:Y��z��:�}t-�2��S�:X1��r���!���d!���P�瓛9��e��S���C��C�|�6bP'耞��ee�����u;�'��<r�\{s�h���cD�)/K�ڛ�IN�K`��Ɏ���h��A�Fzλ�q7 �Y(�^��w��[ub�Q��:�$9�{k{9�d7�:���b���Z����Z��������
;Д5�*�>��}��sw��F��.|�+���0�An��o�D��z)U���p�#7`t�\��ާ�Y0�e��C��H�����+2]���ݗ�`�ZR[/���^�HxBLQ����65~o95_��X�b�$��[ �z���i��[�2!#F���A��a-�>3���Gʿ_���E>�4�u�<!&eL�M"�9�P��R���>`��G'��o���gr����X�:m���D}s�!z��9X����T�^$+e�;�]Ý������א��]A�LWV�F�dΓ#q���x��Ʋ���h�9N�O���i�9��*���#��0Uǡ�a�� ���'|����cW�9��Wh(�xk�4��4�s%�<�k�,��s�*�����C��с�i�OQ]�8�R�va�aP�h����I.�x��ܳ\TƟƀn�����(�����en���!o�Ϋ����C�8��KJʠ��!�i�����>����	xψט:V�w�{�2����I;{=k�e�eN��R���?~:�U��Y��+�Yh��g�F ���c�����88+��z����Q٬���g�5v�8�i4Z����CB|�{�;��D��xҵ�^[\��ҡS��9���_mV�-����UV95ߪ�W���{���g�C����LR^v�<�"|IT�3��ah[C�*��{Ip���4��`��������̜��_�7,K*'J�uEuܚ�B�{��r?���f_!� Kӣ:	up�	E�u�ZX196���e��T������M�Y��ާ���Ȳ������2Ӑ� �6Ä�#�/D�?���g 	,L$:`���_�a���מ���*��?p�iq�-��s��_�i��}p�|~Z%���zT�M��2�K0w���6� ~d�,�+�~`	����Vg5�����f�`ͽ"���^�x�&]�
>�KS|؃�P$�+O��V�'��*����kY�	���-���-�U�'W���E�20g7�|A�}�r��2��`���V�|G��������:�*un����t�`���r�k�����y�����A	��
w��y~2���Q��HX��Ք� Pk�k���:��Fts�f>���&P˻>�U�Ǵ'`���B���.ό���"�if�7 �P�R��p�rP�V��x	��y	$���֝u����*�/�ڎl '�Y�t_]��a	}mCY�i�!c�����6�U��<����2��^����h���NeV���`E�>�
��XK��u�"����-�Z!>�\vϓ��7Z�(1�O��tM�O�gҌ��B<B��K����V�O����p���F��R�B�&����PۤPNHr]��}�9�j_�&�;F �j*G�Z	�*M�:�o��B᫁���j=�˱�*`�Zھ���L�fp�(Ȕ�\q�`�k�r�b��B���GS��`N�ʓ����ü��+��ѐ�a���Ey9��o��U�Z5���cX�����d6���5�t��d4z��%�H�U��Ԧ���LvP��:3�e�th���Za3��P��O_����{�[�)���#n����Q�!�/23o��2��p?���8���v{A���5��Gn���=��z'��]�q�U>��s���u끆���nL�P�J�3�|-����TyȮ��`A�2��ҍ�L?3g1yS��ۛ瞧�o�[�i������\�5���}�<�)¥��|��|���<w���>��PDŧMS�"�~��ё�%�m,�Np�Ԩ5+pk��n��'�j�WEw������9�(�B4٘ٞ��C',��%����9}�^�k4EC�)��Q@�eV��[�:��3���u���?_"V{�xmm�36��L��~�Ɨ5�H!��wy!a�9�<�;ΗD���w��;�$Q�8���nu�tX�3����*��A�&~�����G��hgN����R��A&>E�Eѓ�=?�7N>3\I�}K+��r�ʡѭ��+a���7Ą�_C��a*���P�A#��
o��){��54ڱ�f��̲���/�Z�ك1����l ؃321Z��+��}U�ɼ�d�j�M��_�*Wȃ�x~���
y���{��&���&�K����h���`$ޏ<p�5�JL<o2�̨pk��	7���up���v�f3�*��U���
 �����'u�dĪ+i��s,`���K�gÏ�id�0Ô7����Zp`���>p����ٿ���9u���N��^���V�1�l؃Q�^m������6{��Q�V�k�C�������-��G�~4"lF�yu�m^�����h�V��9J�C���&��_n�w@F��a�c ��!N��p��{��d�uk��o����=��w�C�@<����������$����tcV���2V-㙃�% 3���~�M0+��Ϫ	y\�ÊA|��py&��g�.=��d�pr�=�����X~])|C���*C��=�����.Y���<��i���Qݢ���ӇN�=���N�i���QQsB�$]u�WR�j	{���i������3�M=b_ї�{h^�m#����j�U&�7�Z|=�v7w���N�v:7�P|�GCZ���"kw� �p��F��,��/d#>0�Q�-_XN������� �LX����7H�D{���y�\�"��V���Z��[	_��oi;�uy�Ϙ���LY�,2< N�����(���� �`�8s�͌Q�mD!ﺞh�%�@8��3� �  O�4��|d&�Y$Woo�F�T��}�^��e�Ӽ�~���}j�O\��u.[��ף`a��J���s|B ��jBq*�_4��+�>i[�٣z��c0T�������%8f3� ,��|ͽ���x�p�^��v�
�ؿn�Ϯ���x����ӵ���J����y��0y��ְ�^�X�� Da~�R�&�;�{0`�1�c�k�6Y���s�fi������F[���hࢦ���:��S
,$z�룰���&��jw�F?X�������Zо Z����^!�1�� \�Mjʩ�Zä7���R��%�u��<��]g��IC!,�`�ޑ�c�� �Z+�e6y���B�R�W���t�\|�Bx��^O3_g�i�A8�L�zV���o��z���V��i��|� ��q��L���L�'B�B ��/)(���a�A$�y��!Q�'�Cxf�}r������5 8��8˙�u蓶�s�]�A��B���
���7i����"��oں2�u�	u��X��
Zoj�_�U��H���x:���,�Qa�p�ia:�4�I�|�DC�4e�ot^�n�q�W���C���Z&ϕ�zt�~�H�O>���һsAY�x�_*ח����!�����?��1��B�}�ʏ
��`�=}G�TC�~��m�g�R�G����h���vq�^��H��Ո@-mWE�_��z�1�E�A�dwؼ����[�V��l�wܟ�6��(�� �$�xY�p0�zA��:���/���/Q�T|��� )� y��l	�<G?x$O���?�qn�bd_�]�)VC�+�����k΂j%`|�L��H(�6�"G��>���A��c8*$����h���R���O���ZygP�:.g{檻�;L�9�o �.TҬ��#q��WưOt�r(;�j�Y���~v��}��u�VB�J���jrOZ��/s�&�a�
���
Gή�D�ᤷ�I�� ef��˝u&C��#ό��u�#�����[a�}�QAG�pRX���F��]���bC-1$�r���ϥې��x�k	C�z�����Z�`�B�̽�Ӿ#4����+\���W�rl��d�Ib�"�����5�=b����`7*�Xh������	.������G_�����ڄm.4-�����������x팙��#�Q1w��%�fg�fۀ>��'ǩyʖ&O��$^��'k�CL��p�A4
:k��n�Q� a�j~_4������pv1� �&���@�k�"�kR0�`��q@&���O�jS�����3��M�rN�D'֞|���1�RZ�Z~�}މ7�\�����i���׻a
���[�++`߆	ʽ���3��^���V��L��Hr�Kx�I�4����������}"y;M�pn�}s7y��3����]��p®H������3=��k�IX�Jg2\՜|�&�D���P�x�����������,޿            x���K��6��Ϭ_�{ړ6�7�7K��K�[a]�Bu��
W{���i���L ,�A�#l�H$2�| Ś/��S8����0��S�����w���s����u�����GÜ�oZ���o>?�7���o����o������wCln������~��7LoD�}��Ƽ�w�񴅧�>t��_������Ë�[��0����l>t��~O���|0��p�v��ԜƩ�j~8t��_��}����p�cZ�_؊�n~�Oχ=�8O7���o�c�v;���^pB
%!ڍin�����~��nw���Oð�>^2z��X�\&��e�g��7	x��Ѡ�V�R}�@����͆��m����|�?���/�ȵoZ�c�/���}�a��<����p�1���}�$u.6�7?�f��F�����Oe�ܛd�6L4?l{��� ��o���Ygi�A��A��q{�q�e8��q�����7|p��U�e#=d�Dz;<�i,�"�I�
�a�/���T���Cߟ*��o8|�������h>���a[[8P���B�O_
S�/VO:�R����h\(P���-�K�7�B!��| ����>�|x���7���}�K7
�43��y�_��+�s��y��c��ο�+�hn6�[��z���ͻ����e6H�ա��Es����0�_�F��8<UEIZ"`���f���������6O>Λ����������0�`$�]!V�F���刢<%O�	,���8Uh&㧚�I��i�{x>� ��xn����6o��y����ٍJP�r^��{�B�"�}��{�
�(X<��hT��y����=t�,�������Cb/���7Ll�j��5]L4��ɖ|M���aNO��Q(�����$P�r[�g-�A���זl�4�m)X9�z�F	r��G�K�=/���n���Ԓޥ����uS�=��R��N�vB��,�ݿ��;�^����Q�6�������w��\t���
�:�/G$,����=����	����cw��x2�������q�w��ퟠn��q(ݾw)�F����/O���Ϳ�D�����+������o�:���ܔ#. �ް�>�w4�/����t6�V$.E�]s8��||��@qS�p�\n�l�D����=�~z�F��8����	H����Xٖ-}��H]1�gm�kT��kP"MC�;<�YD��@�&a�;m��}<�����}�^(uW(�!b#]f'���&=�>|�jZ�Q4�}��yx��y�Dk3�3�� ț��p�G��{cW���S��67�eX������p�1���)�y8� P	�"1G�^���N��{��~��	����dy�?(��g�|�~��T��2��4?v�G4�A}' Lp2�%�,,џ}��Gc:�6��`��k~�.��f��g�����[9�F��h P��>�� oɩ���N�c�	������ω�,g7����c�	���mac`�Ax��zڰ?���B�0������;��s���P���V�+���g�*�P�4����F����A�m�_�/�}nAx�5(R�TAS���"0�s _�E�y�?����h
%�-I�ǭoN�����ۘ�y�{9n�����ƨ��p�Y."CPp�
�:����WP�>�R�;
rLP�ў�]YIAC�e"ӂ����3�%}��h7�p?��`���WT����m�G����;�S��4!����uԽ|E�g��M���[1��	S �zcl��A�?R[K;t��[�86n�E�P���a���Ek�o4:Sg�B
Ĳ&@C�?`� ���:�7<Qp%7�K���7�p�E�&�z*�2.74Q���y�I�`x�<��$��0��C�����$�`(��`��� &��ӭ�99k��f�{~���.�_�b�ֲ��D��3~�8����E^�X��&V�`��߸�����V��<?\n5�+x)d�ݚ�JDX�sR���������'��o����!ĺ;=èĉ�#�y>�DT��M6��q��>Ϗ���|D6��ʼ���%�lT���+1u%1�P���,v��Y*�N�v�l�o��BY�y5N�_�Jm9;�ܕ�)�[mX{6SӸy��J$�d��jk��Ge M��0���	kz��Z�����j�v%>;It"`�Z��\߭%2E)�X��Qư5a�x/���k�xj����n�s�����sX�g�<j�w2�����	���/�qd�1�sQA���
�"���8�%���ԕ��M���:ӫ9�y�Gl.�q�^�[��X�W!�̯�@t��K�<�RG��6o�ddNi�z�f 9��6�8����$��_��\�(�6�qy�3��Ʃ�\�X,u�W`���9	�\���4���ϸ�ɉ�R��w9[��7]���Ʌ�Z2� a�V��4�mI#@��_�������\�[dQp_y51�J1�p�{�%d�ꄍK+�2OW����\���\��2� �H̕E[�``��Jb�r��=ٮ��it��%[����`�]��5�\
M�~�]$�d��͔�׀s�h^A;�Z �i����ŗ��S3�ѬKs��=�{&m�3Z�:S�L	Y�kIw^�����8��bNB�6$�j�"�t���.�T���/�f��S�mx�K�@��le��{c�*���L.2%�t�}�v?Y�<sFJt%J���+�7�$���:�tS�y���6��ҙ�?�����T,B���7�������TKS�^z��[ �ݩ�9;�$�#c�]���'R~|{���+q���<h0i��&�?�6�<�cL�Z�ؚ0��
̂;W!9�4��9p���W ��'�(!8���+�"�2�d��A�Z�$�kSi��B�`g0Y��\��3v'M���Wؼ���s����z��*@������(3n`pG*�v
Ҟz�dd�+�Ӛ��x�U騘�v>Q�t�L���>m�	�~WI�鐿g�͑�����d��	7���7{T5�����Ē��'� ��$�f�Z�2��`E����\H��a*8��V2`�ؑt����;��U��6A ���F���5S����V�p���ݮK����`��|��������mW��jCj����Wߝ~���4��M�a�5_�Sԋ�Z�{C�줷���n��LrBu���?�	��5�-��$�C�D��y��R�ҾCDbe��1����t��֬j>m����v�?����c!�Ȭ.`���+���l��� �sY[����$�nM1���?�y|IԇJ��J�E�-�m�۱�����V��^9�'�B3`ؠ�؇��Ǐ���[���6z��a�*3�z& IY'�_���Uve3ȜqN���\�[n	�sn���r�E�X�Mg�9<,�@S����f��gRt��v�A�C��v�*������V�v1iv�
����Y*j����w!��[y1$�t��*o�E���04K0V���2%�+���pK%�Ђ��+�0�f@T�[��n��Ǆjñ��2TL332�/c�L��P_���_���*P��9<@\����>��E�x	la��S�	L� ۢ�Kv�d�_e?�
X��r�8��r48@���`+D(s�^�><��Rί�A���%LMhY�lC����6�|���b�!-�u:a8���i���8uU~E�-���v��30�ܬ�����55��ZC:%M(wW�Ф�I��\�W'<vS��1��ZP�+ń��B31u��ׁ�v!ʅ\�����6Ϋ��L{KpW!Yą���y�����L� v�g�>Mǅ[�����`�����5����"�%b:�K���&(��K��#��S�*(������B��G`J����J�#�J���V4�iW@遨��FD�WP��z$�V������k�vs�V�@Q�w�W�a�mw6��X8z�?�}�Sk����U��7��P��q��ڠ�*
�&s�=����>@�c�����p�2<����*;3(�������Z��Z+�������tK��� S  ��*��)ɀ�R�1��]��3	\T͛O/�}X�.�J�H9Ur"3̚��O��p��3zg�2��p��Vk�dH����1,w@lD��O&"�h]�<c8K�X :!mҮ�ɶ������6o
y�`��._�o��$�z0t�%�F�p�$Uڢ۹S �^7S�N3D1�T��-�p������VO�1�+㺚�i&!a��x!2��֔�$�� ��ɓw>�B���Q��D�ʎ(l�ʎGH?�3a#���y��A��[:΍Iw�X?�O���*���46�����?��%�i��s��^�f\Q�X3�h1��6�$���0����.����YŪ�(<ˣ�����+U��Q4k��vxז�ܤ��H[�FAY�l�U~�����1�ʲ�q��tp(�C�f,��,��~؄^nG�N�&�=B�����/da�����j�L��8(CwK���=��j3qծz����b�}H�d��~K��eMcom��a�)��n&%YP�	Q�%�+C��X���$���Ԡ����S�� ����~~&���o���O#�b��pQ.���˧Mu�.u�Z�d��-?n�O�����H��x5CF0��3X�gm޾8�&ڬ�<�� b�N����$���~tz����2�v��$Z9��1�K��鲔4Zmn�*1L�uY�I�jI������K!Z3Od�y�~9���V��Jdc�UZ����h�%*�&�R46ᰠ`�EF�M�p8X06�j���c@jD��,ϣNp����)P<F��T���`�$�Ym>�9(S��6NYOգ$��%Na�,�B�$��gn�Y��&�!n�!KY���S־�L�$�
����@�k�7g��@I�dm���Ձn�e!R�f�X�/+�k��u�|6�:)��(� �C��r����)|���j�f��!�+Ι��Q�a;ߐ"����$�T~����_��9�O�1:��y��w�[s��@�s�W��:(F���`�w~r�Śp��i�	�ż�l�M5,��)��+��6�ͧkd�ŧ��w��+i�P5 ,�Di�bH}��9U*�to�f= ��k�>09ʓu���A�g�f��!�:�0)�M�s8G�V#��ds(X�yR'��ĝ��
����|�/u��]J��KxD���A<���R/	���ZxS��W��AySwa��2��B��$N��օ�jB�9L�+�piSΑ���2b��?u�"�;(T�X����4&Q�j&��+M1�{��>u,�@\�Jǃ&�~���ÊiI�#�W�
N�+3�X�#��!���$�r,��]�s	k���@���*�qvZ�N����ĕ3w��9�a�P5B@=W����6<�X��#�$<�H��C���aB�:p��D�p\D���<n(R0&F>Z\��ɖK@���tך��bn��	���s!��z�jC�[h]G�uR��Z���Y�N��Ym�Y1˞��<M.K�9F\��G<�M0��y#�	1kL�g�ak҂3E o���L���{)�l�Qa�ݞD���~ST0|����*Ҿq%�f qM��H�)6z���^&K����2�І�JDqAЙ�x�usb�f�
B,�&�(l;��������q4�U!�R��W۬_�9,3X���܈V�q6��'�A�l-(��rmM�V�!ƚ\]��՗��L"��V!�Y�i����+�1?doL֭��/����<�Zr������L��r������c��w]8�� K����_M��
�x�SW�cQ�7��O���	@V�J��.E��hC�[K��p�z�,�+�,*�[M�y[��v#��:�L�0���ʅ#R���	��H��
��&����V�!��L0�<W���I��rpj-Mf%0�C��a�Y��%��G]�f5PVϐR��l����n4��1ٺ�T9�$��K�g�8i%T�]�
�ee�4����_JjH< �J��gߨ�O2��++J�G��TY�5����LY9����$[2�X&Ⴭ�R���PJ�L��T�+�W&e��Y �<���+y��&Ӽ�?�,��E��99�J���e�L�_H� �EM����{���dw!�*���l�����N��Z���-�5292rE�QQ����v-DV�<�&>#O�ςd�覿X��Z��Mb���`�9���&J��I�G��b-H�~��_�%���&K�j�]-R�W�d���;)��R�����v��J���-®&�"ؠ�+0Q^y����_sᰪ�y�4����S.� ���}����~��������E���{&��^J��&s ��x)�ʺ�([�W��DYt���3�4�J
9Aڵ@�3�	���+	��TJ_;����
��6���\wU�|��*���E��'��R�u8I`��z�̯��c�R-��9J�k���:�ky�oaj�ʬ�Ɋ����j��^�����uP��.T����U`��K��:����'}�캮EN+ْ�c�RWԮMOJ��y+�W��8�Z�,PH�����
�,���8�Z���@����_�Srn���]�˪�Jn���Y�m��&iث�����8��ګy̬�8��Af�^-SfA�Zm���
cr��/�|��1s�!G�֚���L�FKd�j̬6Sh�;�<|�.e鋾a��jc��!m{c�+��EN�O�Y�z�:���t��4�Eb�+��t���K�.���W�I�^ɗ���D��˪5�tf�Z�,VV�"�K."f��/tˬ�eD5ϗ�A_Kq�[�G�Z�(�^���_� �pŅ��h�_�B.H7��R���_.�nɞ.5F�IC�����2kƒ�%�^���_�μ.=�[m��3��+H�犩}@�N�$��K:LUmn4�A�zʀ�����f��3��W         �  x�mZ;�5;�箂@�%�R�쀄��`�t{n�o�����xdYR�1������������������͞��ψ��VF�c�M�x����Ǣ'd=���i��Ŧ�#C;g�a�eȱW޽Ql�P�l�_�j�B�z�͇k�}f�[����|�g�#$YO� �;��F9�M(jf��,�A�导Ω�|8��,���x<��?]֌'�+�m�R�y���D>[P�|A��A/�6�`���J(S���g�����}�(��O�'؛<���$Pd$�����KYC1�*� .^ס��>��1ړ���b��:D�P�\���1˵��e�]nn�,�������>!z>0\W�%��M֜bsU17˫�[η�>+fQr� �ʂ�d���KH^л��U�l1�dh�E��/�:"�����?bg��=%��[��~�Dv���W�V���u�//gno<��oa�h��r�4]ݛ�&�/�I�V�Q}��K��+P���w���� �ۭ����J��(U4�x��꒣b��U3z�@�]6��A��ȭ�#r�BM�
I+DgܔSy�8�@�j�\�To�g5g�t�]�xK����K�Y�{r�)�4�5U��c�|�!��
B�Ů.�5&7��q]e�V>m�R��&��+tL/���Y舗�$�&?I��#-��A>�J�n`a=޷�5܌Q�*V���kF~�X�$�zge�F26]��C������U�s�o�������M)r���Z"�G��!f��E��@�]��5�k����g5���.�E��`�9�h�j4،�b9dh���.{�pS��>�Q�/E�<{�Z���ʌ{Z��^���J�D�j`4$eG�b֬sĂYE���UV�$;,-�YZ�^��Z�J�hJRt�����e/�^1Vn�AΌN-�E���X��3�jn�jT+~QO�9�G7;4-�3x@��Vq�� jm��5@����luh�h�|�XE-&���Ih�-�"xZ�~�.��z]�i5a�:iZȖW�U������:6D��4!O�F	$7Ҵ���U��b�$���zx��.K�H3f�+�%�4����C7'�g}p�4���Y�nI	¸6Iѥ)U�=cѬr���>;K�jP�j���r�[f�l���B�QK���A�*k�/�-}kY��.�1J3�^*)#Ak̇;J�l�gu�=J�6 ��*�7AKB�<�#��]WY�?]��t��� i����J�4��[�=G|�vhM�YGk[�-����(y�%eqpt�Gg)˽�b��ִ��Z�����*38Z������7���`h�#g%��.�\wf{���9S�a--V������ZZ��C��,��I�R���hm��tP��s��t�W(y���VsI� ���Q�P�Z�z���R�z/��h�6�5H��6]�dIT�N��-N�v����w0��$��k�bYNQ;�ZJ}gS{�n]�b/mmg_[�D-@lѻG�2p��B�>��A%���]�Ӧ�F)<�O�I���U	��vVҪ#V�R�:�Z���5��x%w���O��pp���5��-�:����ا�C��U%�&LN�V�"U�U�@�4��Ec@G�,��h\�:��o�KA�:�%��[����$kF{�'��:�c=-����.ͪ�\-�}���u\I�6�mkc"�t��ӊ�M����ZǑ�z�L�I�V�)8OP���E�^�:%�
Ӫr2�*���$_.L��^��C�ۅ���D�GTn�Ҧ���녦"��$XJ몥�� K�����0XJ�^iZ�2���(��l)@�l��� ���c��v
v�����*�ݒy	Z��o�t�:�	ܒnU3֘un�覘��P���
 f�'�Zj)B �J:T:�I�n�.M���a(���h��5TBzuH���P�{�f��%8���Y?P+i�Z=Ʀ�PG��N��t�Y�I�.M� 9������E^-i�������f����Â���������ͫ�7�S��d%0������5���q�p]1����;�*x���^�6[��flh�1&�/��8����/��g��\_A|)�������_�<Fy��4�t����"�� �<�Fxis$d��u#�7BBL�����#���K��s�!?��a�J�p��S��,��xV��:�
v`=�O�l��7��Ҿ`�,	�-Zy�-j@x��#���'���~^�5���n��.Ǎ���&�t�B��n����nW4�g.q2�a�/�q/yh�3���}�y#���|��Y̮n`竧Yr^z��%��H���F���g}!j�gv�y����F����x��!��oV�p�N�P�H��(�ҡ�+od���2���� ��$/l*)<���7#����E���{#��7�%p&c��̓��<��M�O��^�o�4��y��𛂌t}hd�䬅�ٜ�_ s��I�}�p�4�odJp��#��5e/Y�t^nĞl�+���e�w�oFp�y�-��[|���̦��kf��R�d����'���-��_�X��O�=?)�J����9�d�l��D�����I`&Gv��t��S.�$�=��lF3����$��q<Ҷ�P� ��!�	;�r�ا+s!]�$�#��N��g\�n�Ԝ���[wF�V7r�70����dU��,���W�I{�kX�H��;��L�Ѽb�Fڅ��`r"VO-?�Ϳnd����d�����l����_W2�ʢ'��{�s#3�.vwބ͹`���[SoB��1��$��zB����~����7�l��Y"��՛Y_�	�̕ӛ�k��H�j��R�`�M��L��� v>��ȹ>�h��cˬ�3�ITZ:SgK..4�eo����3��π�Tl'%o���d���><��,�"��3�I�<��Y���I�ÎO�8�~���BاY�_�VM�8p]>"���)�g��� �ή�b��d�I��)Kd��2 U[+o��>���7��o����2��         h  x�]Y�r�8=���os�AR\����mUylGWt�\ ���鯟�	p鎨C�����{I)�@�Je*-�T]�J�<�A��U��
�+Sj�h���^��,d*���VEBby]%�UyV�&�A�r�O,d ��Y�ծVg{���E�.�ԭX
����4���)�B���OI��Ń꯸��kMۄ�,��"��T�[%l}�eI7JA��0Q$U}1���oleG:�Na殕�Q�-)Jo�*z:3�5әx\�`ٱV���m�vB�"J)�#���gS)q�U���O�%�
�t�B�b]��UU/~t{�ښN�� ��2D<7����p4�Nr�(a$^t]��mל���˛[�8J�m/��JS��%$����͔ʭ���-�8���S��q�TU�mW�v���DT��0�x�G�RG^��c�p\����me�xQ5����[�Dq쓮
���م����z��jUM1����q밙\��_�2�
�|4u�)�I����"��Uٮ�����}1����)���R�ȍC��������{�n���Ŷ\��"Xb�_���j
W����7r���y)�懪����VMW9�P|) �x J�"�i��L�[p�i�\D�XwuKq�U����`%a�l�X¤)QO
�hN�ۍ.?,���M�3�x��NռQD�	|�qX��]��Њ{S��u�=�L$��x��UCLT��C�nF8K'�	��GW�{�)��@AM�D���
�뛣���U!�(��<��	׬�&(�㺔��;�+~ �Fs���p��)A]�E�폥�}��3�+�B)��i�(�}��FK�Ltom���](�D��� ����5]��EY����@�I7A/��*
�*"Pߖ=
��T4��u�`�z�p��j�]�&e�Oˈm��j@Y!VUk���2ƽ��6����U`�ɑ>`H��Y��=���v� �/�!]�����
1�t����I_<9���+�EH.*��N���Ϊ�}�Κ�����;r�d� �J�^I�]��AW��ɺk�G����,#(� �_���F�����r	�������`�#0�t��l�$�ڨ3�״�>�S#���	�� � 4~�E��V��)��
����%�J���Kf��̨�6�U��D8�q	��T�.h-��h�/��W&�]������k$#��xI!��W��U�=z�		n��)�kE\�ū�)[ʁ��|/Q�ݞ*�C0 ]��$&!qoJ��M�E�k�|�g��h�ۂ���l����>O���$��#�[�P�4��$%��A����PAM�u8�5%������;��N�Io����v���b��i����N�V��]d��đ62U���y/JCb�ے�  ��,����4����L�fL%�C��DN���SXq{�(r��a��e�8�Ӯw⅊�G M�)U�}|8�˸�KS��-�	%�U�5^-�+FL�)�W[)����6\�K~�p�vr����O�+��g��ۓ�)|K�d���=0������=B�����+��vV� wS��XN��U/��d�Rf\�:��O_��Nt�l��Q�/�|͢@��|fe�\��ըґ������9�aEJw�OG��}�֓x��;!#������N_t��.7��a����3� bsX ��� ��`$,8B~�
8�H��2��ѺT'�L��R}i�s4�\�Px���n��δ�q��~�.�_G[�5ӡ5y,r��Q��wU��|�3F˗$X�}}�ݕE�֦843�9�Es!M�uM�L4�:O�nm�{T	�1�m����(�\<�Z����4��'����<�#P�;L����zM���b�gۉ_�:W��Oһ;C��s��ω��V&�T���-�9B$6���u�c���νW��_��j���Y$T���ѕ/�lQؓ�A� ���_Օ��3�����x��wHr��9hT��dvV[���6E��\�`�
��Q7�1���[1^T	��WW�;v��yYj/u_��Z�L�Y�ָ����̞xCl='����X��;��<�(�'L2A���W[t��^{�ۚ=R���'Q� z�AUf?m�w|�����"��dv;6���(%���4RxwZG�1O�P��@�lu{��	���0���r�}א�7��h:pIg�]tW�cjWI�]�rH��D�o��,c�9�1r~5#����r��� "���m�����Q=�H$:��v�+\�r�:��IԬ eŏ�r�	�Q�K�c��Hli�����i��-dH��F+�\	�͎Q�x��ͦF�Gk�\y�����dg����Ҝ�Ԡ1$��\��P�4�A<j�s��Ε�Q<cM�]�w�Qj�=x	�^J�rc���k�~p� v���Y5˼���"�ۣ��ֻ�`X��~27��'5E왌�J{��.��������$J��%��@�hB��!�<C.���4ِG;(�h)��g����N<�r�t��H�7��54�x������4��x%�2�[�����9ʠ'�,��3�BPk����M�f�lY. �`'_��HKe��	 �Gt�:����?J!v�8����},�Pŭ�XA����F��&I2f��fA���F!���tk���``���O^A,�A`̒s�����r�\�x�@Ϥ���E��ʖT��k��2F��e0�ay��l����]�Ƃ�`��2v�>�̒�
��^[u�H����"V�$r���i��C�l�f<�t����̜�m�dG����"���CO�i �nL�U?����&�����c�w΃��Gz��%|.��$-,���-v�g��vQ�?T{�A(�+L�q;��lB��F�F,����v�v<�@hUe�U�Y:����M�F���u�ic�&C4�v��[�}���!�!���c��t3���7��j�		wޗ޶5SŮ��5�`��Gt��H�����>�~UJ���:H�MWs<_hIX�n�+��}�՞��ʯ˹�UM���KӨjH��ay�ѭ54|�]���hT'�/a|�i�ݭ�ي2~JH�7��\���!k�j:��pT{���*�4g��R���4G�p��/Z�;7]u�"'�f�y����S����ܬ�t��e����+l�y��jZ�`憧C�a��$��l�� {-�d��/΀�w�`"�UQh�g.P��z7zoJ����<���̸�ޑʺW�_�=�xsg�7�e۫6ǳ���S0�4���/ 5b;����ǕQ��3*�����9�3�0�ʪ�i���`)9�3��LV��_�B����ݤ̆�b�W�P�
������S����!(��b�گ�b�ц�)	�Ǥ#:�*�On��{�q�����W�yn3^�U���$#�5~�'��7�ş�2���Rξ�IXc�4 �A��(;+2�y�4vE���!��h�}t˝@T{q[�gA?���[d����\���)X�7X~}�F4hj���$���y��^����0Ω�����x��0���^9a��4_j���a���Y<����J(<c��T��x������۷�:���      �   �  x�}�Ar�0E������Ʊ�.פ&N2�q���l�AC
J	�"��wH.���W�]������K�������<�̒����G 2r3pg�c��u^�.�Ѡ����#���q�ȁ�{�fì]8���8��2޽B-�[�]8~W��d}(�.����mΤ��N�F%P��g]靑�m��ӮlU@���}�*���t�Ug�����n��=��v#�R�[H������2>p:1�PA)��s
��Sge�������To�?��Y)���;Ƅ�N��`�%�։Lu�0+4�H���1|=�������e�:�M��`������2/e!�p�N����Nx�<�`#�kG�ԕT�.k�	�a���bi Kv�}?�Z%�~��I17
�o�aq;����a*����B��._�s��'�CA\YS߈��M�&:=ޅcba��{n�?ĥ6����G%̏��K�\�'��L�����ka��`��m�;�QS��2�a�k�H���	
�?'�D�"�6�V]b+a�~�c)a�����2�g��Y��o�e�Xq�	i8}�u�&3��ǥ".(�O ΍ʹ�[̣�S��`[�i�kUO����b��>-��+;�+�0�`����R���8%�xo����J����W�;PO��	.8���m����~˄�ܢD\CΫ���e���         Z  x���]nc1���{��`��&f}�
����i�J�d�'p�_R@�D�����G~$|$�����畡�o|'�.I���Š
yH�����]�PR�wI���ʔY�d�"i��:Z���Inw��$3Z�h�vV}�:�<Kl@��0\E�е��N��Qv�j�gbD�4y��bz`3���@�x-ݲ��%�6_Hޗt���}I�{O�".I6S������Ѭ��L���So�Q\��5Y����cR��jm�p��%�#�*��9{��'��u��1-r�]]1���I��u~$��|�~�ۧ�u������O�z[�ݽ^�Ot�XYE��x�A)�q��w94 x��w�ݡ� �f{�Cۼ�	�Y�A$���7�;f��>�2�Z?^��܏τy�c��g	�r�6bYt��a�����=Dk�%���7[t5E��ts5U^�$��	77P��L��l9��Mbd�$�hO�Q�:�R�ƶL�q\����&Yրjp��暌�U���UO��U�:���Q��5E���N�^x���Ww�u|\�Z��m��X��m�4���U�x��� [N����ul9�
���dVm9�~�����EiI      �   8  x�5TAr#7<���R���v%��׮-+{I�BK�4���hd�~}�rR:	 ���~L�����a:��gJ�,yf
�	���i�(E�!"����x>��J���x�Ħ���ݶk]ۉB`�%E��!�H�ӾW��k�H�^]��K&��c��e���ԉX��	�$�3�^��0�Tb,�C�Rp��C[�^|�P�!�!8�t���G��>l�|i�s���B�PT �x�B7�a�˅$䌊�Q��3�f@2dr��Ա�v>�����˰�K��P�Nu_	�T8*�7q��j9�i��4r�9��2�zxY�O%Fa�$�FW�ӺԱ�d��a�B����`��J"h���yi�6�gQ'L���ᴂfoE�u��D�҃�R�h�&��omߠ��H$_,;Qz����N�2��Hm=�e�����Բ`�/B��Ժ���$$p%>F���,��x����� ����R�H�b�!�
��>/��PG|�%e����~i}:i�)�G��m�g��9� R�an�?���`Eo��+)_�|��q��^�O�ô��X��]P�n�a8?�%Ioi��:�S(��%����<jO����	܄L�3�ُ���!�u.m�ҡY�1\�u
�,s]V�Q���G1���ڦ�Ud��(�:�s=��`��׶|����}ļ�K)�Z�~��6��2SC��[q����}�5(x�n!d�.1�JW���L] �����O��܉�!%*c}=O �JJ��.�i��yp����`�]��o�ޟ��W���߆�x��!� ��DO�������Ɲ~��_�8��#.z      
      x�e}K{۸��X�W��G}?I|���p۝���N 	��M�>�hG��w�* s'{{o!$�jU�*�z�.������U��-��V��=����zq������e���e�1~@��j����iw}��/�K���Z%����xǇ��o]��CJ���[��l�i��~������G��|)�	����x�Wӎ��[Vk�u��C�ō����x�C�}t�e��ݻ��٫Y\�㱱�Qd%^��j���ٮ[���l��2�u�߁a�u����.>��%+W�Cx�j��:>>���|��V'�-9ƿc�^|�;�����k�^a5�aA�p?m۵�h_��Ȁ���u����,�e�����d��)8��1��m���_k�F߲�s��1x������u��'�)d&��t��M�-n�q�/�����eƔ�KӶ�χ�?� �����J��_���5����T�%<d�\\���uc/(��,6<���[+��i�ck62��oR�Ƌ�W���o���ķ�dqS�؃���h���9�4*�tc���>�"�,b�:��ջ}���?�w������o?(_|����_�a?�&�m���7�n��؟��}u��ʼ�ة��Z]Bnx�u���㾶���nk/X�J�,����b������"�V�t%��aX�q�ͰPf'����݈���5������/��]I���a �X��I�=q��H�8k���k�8��v��A���l����t�g>����/��:��.n�u�]��e>a��'�o)�������89�P�=�0f3��[��_Xd?�Z<�f��?���P=�Q�������;k�b%1d)k��A�Z���,��T!U"�A{�!�X,��7��рdqO��-���(DxU�_�p�S(���uo��aW�a�"�N0RQuc]#�s�?�|q6b�-���rs�߲��M')Nj�a�p��fS�N��"�PV��������oF'�������[1:�ha�N����`{(������<�#έ5m���=�붦��_�^���As����u�xM!�C�'l�iaɋ�J�R��u=xA�d���d��~<���w�ƈ`r��ȼe9�Rsz:h${���TM� �C��M��-.�~;�G'�E8oY�8��3��M>oѯџ���޼C+|�z1	���'J�r�?���v��RE�ů�x8ӓ���Z����r;�%I� �kH����{,��;�"��p,ry�+��<=55_$��<]|j�� '��m��G.J6W�y�G`���N�4,����na�[8n�W�j��a�<
*��n�-����:hzO��6����{?g��� Py�hk�ԁj;nP��bI���H��Y񗰂�h2���
����x%N��*����u0)�^���96N�-�.�*���	zsi���?(�м�ZQ�%^�ʝ�-np@�	'�ζ�?p(���Np��c�l[wp'MW�C����nL�iB�IO%��Nx?tƙ���WQ�0��>g[�do�WxE�V%u.}�]��L��q�K�P'�������N�!Z�������������I{���1��u�����|w�v����%>�����cI���׭�o� �":�N��9>f�y<t'���r�h�&jZq�o��v|��s_�謔�a���՗f+
/WK����V~�W:m�:<��@LƠZR_�F���^>����O�����g��X�O�v���8���y7��{快�m�q�7ԛypS����)�5;�����e8�t���}ռZ�	�&��-�#DEO�ٔ�9�~P��w����Im�!�KUi������B��-q���u{�A6���� ��%���	z��wo��}�� 1+�Ʒ�r�ϚWV�})B���Z������f.տXO�8�_5�WGu�*��͉������n�b�b�@+e���6��h񧳕̹�A�8��5G]u� �۵{�17��^w���4��z�O��
 ����)A��f��^Q)>�!5h	|�1*Z�x�P��*~��n�>q�U)
�/f.B�����kgb�XHW�z:�f �~���D�L_���Jk8��l�tձ�Zᡗ4�İ���B�=_%PC<�'�#lV��p$����>k^Dnܩ�v��3�#^��:?#��#4ו/(�78+�n�J$��0wIW�G�|+H�)�	;B9�u|�k�x=w.�{x00���R��"�"�$+�����#�ܦ�2����+|���\�A<�L\58Wp��>vp�����^�
��#�Z9�K&㽂 ]'7<@��]�i������܌;S��db&�V��z�B�&E6��W8�V��n860�o`�����[�}��m9��P�5��d�
 ��?�ҕ�)@�;@�}�c�q��@�i�ܸ��ϵ�K)x�
 ����T���L��*- 9��F�fo���ʜ�U�(ߨ��M��lj�7f+ �;���햆
�rr���W0�EdY�]Y�i� �n�XE���x8��|��3ԭ��/�ӹ�,�
x�~yq�ix��	����P�ъ��Y3�"Z�X�R�MS�`v crя���3~�@ݰNtS�����m����<�{�ɀR*k���h�@�ݯ`AWQ�ddwSNE��t>G��Ǳ�c�r���*� ��h�<��o����O�%�Ń6Ŀ�_ն�q�.�P��[w��nl�ܳ�i%3BhxEP��Gkqt3QV�l�]vh����V�=�D"ӑ�SƝ%�V����yî�0L�C��P=�G-��,g��������� c)�t�" �s�sX���s+��5�G`>LrG��	�v[;�f�pN_[�X-g�_?;�̦� ^�#���P��i�/��M4��DRyd>�-��`���Zx� xnEP�'SN[FN�
(��ZCb���'Q�3�:t���n5$��]
����{�42[4[�]�8��f��C� ��~����w��F�FyN*c�"t�kq4a�p���C�ɇM?t��;�:��p ��@���o'0LYQ ���ݚ�`ը��D ^�#�%T $I�r�+0 ]�s���-��z��w�������պ��&�𻨢��g��Z-T+���W�>�� 1s>L9�,���cõ���'���0�硾7����~45�ڏ�����i2- ����xA�}�N?:;\�{ �C(��%���>Ѕ_.1��(FD�q�*�@�Y�!���S=�h��S2l��@BQ=O��8 _еe:����'b��������aؗ��5�"Q7���"(GF;�{�#�ɤ� �����<l4n$�������5`mq6h|z%l*��ٗ��NN��\ ?�J����<M#��Q-�܈ ލ/P/���^����i�6ŌVf�P��;8��_�ik	���
��%w@C�zG��c��j�R2m
��(��~��M�lƣ;�ْ
��]�A�w�\���	: ��I�}	�U�,�Nx�z��(/|�!J�`�.������,C�f-��j�?6"����۷^2]�4��j��y5�=���?p��r�:��8ܿf�g�t��zvW�D�f�@g�2�����:��o]�w%�G�	֜���|�ƚ]HpU���7��࿚|���~���D��y�\���ͤD�p)a��]����vdj��D�1�J���~z�Ƴ�t�s��`;q��ʝu�$���z��3� �c�7��4"� ��jɊ��#��D|W~:���pZ�Z��;aN��ɋ�[=��'u}�u�*�L{nǾ�!�!	7�f܎ƀ�Qs�;G{�k<����ƕJg�C
�]�&�8�QLh���h܁��H>}Ǡ�L �<T�&t�FA,^i��
�� �7ݨ��R�	އYC�^GU�wx
6��a�j:���Q� JP��m�k&���I�z׈�C�v=e!sw�0'e�Ti?�?D����n 6�9M����!wf��ս ���]����'�d�UN��:I$�B����vo֌r���w���G    {���B&��5p����!����aҶ�z�M�� ��)�n_Gb�i��g�f�s�Su#J>��z�+;پ�&��A_��xU��KM�NK�xg_��د��=�U'+	0ky��0X��<�!�+�z���g����d�������
k<�m���N+I��@�ߛ��6<Q]y�o��딢�?��`�ɡ�r��z|�	�¼���з�8��;�D,����]���͔P��j��_�WIB��R�TR�u����l���*�{P���D�m�=;�WF!�5�$@�	�7s�q`49����������0f�  �7��ԺWJS�� Rcgߝ�3Ӵ�����0�[	�?�1]���� ?^��K�מ�!aODYg�f��^��۶�}�1�8 �gpj6p4�L�7N3h�h>��ޘ���pp��tf�#?w�Im�ۚHR�\ �K�����yr�t5�&�xf�lK��L~3}���,�To�qp�8\�f<{jE�~���(8�� /��H"�}�!y�,MxL��'��/�&���0�s
�Ė�3�Us�h�G��^��C8�;��=��E���u���|�A
&��e��9�J'��x���-�'g9V1/`��D~�WA�� ,��<�[.d��	�xS��@_�vX �ش,��_k�
��8O���{Y���`�;|s��Qq1��Y`�C�����E�ZUz�d���z�j�,H��eOn�G3��#�S�^	�9΅�Y�"P�q׈�Q���"	D���j�)t�� F�0|��}��U�Æ�m�*u�S��N���{�'��!�3��bf"��#��B�.�����c����JTp({�*3h�o�ys�YN�2V:i�h���Rt����j�d�ȓԹ��V�xK�ſu��-�M�.�5��+� ��fP���T�ORP�~�p�m�m��WE�X@~6m7`w!J���@V�$��@~�[O�(�
�uHE���d����.W5g��?1ԏ������m:�2�GX��K��;��Y2`�Tφg�6�4��C��O�!_&�� 2���ŕ�oj�W��/����>��X�J>yR�	��rHG�~���5*�$� �d��u��ub&&X�[�"���92�&�2�1��-�u�^nC�KxQ�;y:���K8�������C��1F�@��ߙ��(ٟ��5��7|%����.� ����m!��˙虘8�	�y��	��Ծ�P�./�>OV��wX�sPx����	��Yo6b��|�t��ٝY�����|v�nQ%�a����H����O|'
���y�,���Q���y"V���kv5��^�r�>�tP5� �o ����8<��!���\>��\&���1}��ӀU0#���;�ɞ�d�yFC̈%!F�1�!��i|��7p�u�9�J�%�
3�tn�Y��<a�`H�wG�rn?9t���/�WܐFz8�]���P�>�a��\�TQ��BHjO|\�Jp,���,9kl�y3�~{�ʚH� ����T`��]�z6@�h9�WC��;��s����	��ӽ�6�a\�:0�܃֚T"�c7b�>�=����� П�~�R���l��fR3�q�s�x��j���z"[͝����ĝ?��s���d9�ū��~����^�l�w����-�d�.�A�5<���
(����1\L�3�4��m٬V.�F��`����t�!e��Q��l��Җ����p�kM^"yB�ȔyMO�5��&s� ����=�!A�#�����:Ak֚�[�y(	@�5L	Lvl�@�HC�%:<k����ס�T���1]�\\�|_��߻�M6����;�$#kB�4|��B�7r���=�3Q�c�i�1b�
��A��)^G�B�I�C\ŋ=�%gI�70�3��w?�Ǿ4��D��3������BWzLPa��7d܎�B
&�@�s�o����(�#L�R\S_�5��{������P㢆ѭ���$�� ����þט��$_
٩;��8l���샠�H(�d��\(/�=�±Ѭ�e����=,T�{я�a=%��AC9|�;�='���W5G�
����^R�ͦ�G���9\x����g�����_��Ǘ ȐQ�����x0�����FJ4��RHXG���ҿ�lvX!�� ߍ;���L�u&<�`��5V�K�����@�tP��b,gCR������E5$��7 !]j�%̋�nCN?�O. �y��%���J���GIFTt�tqx�Sb"�
G9ZF����1ԏ�o��yj�� �gs�� T�@��Lo $ ����6������� ��C�f8n���'n:�@��W-�6��y�[#�V�d�~��3�p�V$'��i��{���0E��c�Xԛf��~�zG?��j������>��Qc��N8�|{�r>˘� ���cߵ�FcvO.��іH���R�}��61z�B��W�q�#��u�I�S_}y�=-2r* �V�3H*l[uC�
��g&��H�$�鋦���p	/�j�$�-'LZ8Q����o�	�	��]��C����]P6@~�p:v�)x��dU���<p��-�����ɕ	��K���L_��V�e�,�i���H����$}�	>�[-������Z��>����.X�m�)5��^G��3�s�
g@+�-�X��J\z#��sL���A�+����>�Ϊ�R��9���_ܝR�0�9e�W�8;{u�U�݂T�q�!�蚃q�A��I�{Wt�j(�i�Qꇭ��닑Tq������z<���%����w��z�uLmI!rP�܋��F��Pa����XF�!Sb��^�#c��x2[�M�X�l�å�#��g��ۣa@�Gٕ����~bސ&�EMH�|!�W�7���2ɛW�b� �92G���d��Yv2]3yՓEI�_ᙢ�)��10�*�dv��+�֎S���&���n���j�
�����_��'�����L���Y��w�l�Oρ4�tME���㑪���-�*�-�RE����t��G1[��*�qy���V�V�sG0��<zv;!�l@�i#���O��_Ѹ
�ݔ)�S$�Ǌ���3 ��c�����@����w��|fF�W=Ą�4I����O�.�Z���0��p�l���<n:G�V�v��r����?!g��lB
�&rG�*-B��}B*$��l��*��g��D� ��)�m'��Mf�w��k��~�^(�@���,$%���z'�b�w1鴔��ϖ�yI�;XZ���y��=��w=�J��B��Τ��vjh=�oF��E�'�t��)��T҅�e$�X��5��u�p;/Y��@��q��tM������*4����$K��$F�˄xP���k�b�8�����ǭ�B����
���`1!�����ᅘ��j�O���f����G�d�s���\�BY�^D�Xj�b�4U�/��Eb)�VoT��aS;�%�&�@�C��GP]PT1�L��ܩе�ݰ	�T���4Yf��S����4��"�|�'j��`���-�P5����)p�����u��jeBV�C�)p ����'��3��yYg�k�y9�WW�� � �^�D�kW��,B
)�����U�~}?4�8~z�6lj�����Ѐ��t��}{E�6����d���&R�������)X�^�=��,t4��y���d�* ���{�O�PzdtJ�h�q�j�R��v*�J�(��{���N�YǷ N�
��g38���P���\�/�.n�NLxO���n�N��!�1�YVxZ�̓��&w�!�)%M��0���.Y�ً��Bc滰��Q�A�͉	) ᝑ4�9m��Dd"8A� ��ˊ�Fy��8����  ��?8��#QRs<%�1���븅w=Ԯ�9
���������_��	��`Z2���,��e�T"��O����p��>��2V�
V�� o
�TPݑ��W*�~��6f�<E���$��Ya.�~ǧ�tpY    m��ݺr��(��#�ñ��ܕ������=ȺS�^�z�Ɂ7�<׽q��|��Bd�D��;5�$f.��&UےM�a۽Ԥ;9�-'̒Cs ����D���b�N�lL�m|w�u$(��Gs�=sN����2�͗��E��ˉ�q1����?=X �Ђ!�0#M@��B���Ӄ�������P�8�f8�m���=<��P�8)����~}����[�'�¸b��cݒMso�#��Bv]!eA�`	]��|߳%CK�M���T�ޛ�2|�����#��wؐ���@�tl��Ğ�-��R�C�1K��|��/m�4�f1�f^���]?Yw�@;�T~n)��F�g�Sprr�3!�Op��|Q�4����V"���ɨ�c,bQ �T�l���C�K��^�Z�˱}=A���%#�'Q%�& ��4S�rĖ)��L�T�<��f�wI4��^ܔR�i��kW��8ݽ_ܤ.�3��~���h�_�9Bmx�����8nA�����ȟK��J�t���,I��1��.q�cnD�hw�[��R��$�ɔ���]h��8Q������?��Eh/᧓���a?fB���§���Hb���;���2K���o�7S�t:	�w��ϚW�I�q˕�)AI��m ��{�Y0yP��|$WF=�4f>g ��5���l��z�r�s�D�f���L&��12V!�C'.
CW������ o,�̵��ir�3@�+��a5��w�
2��8t@q
��\.e���gR.��co=w���� @=i�v�|x=�xe) k�^`�R�ɖf@�lGP�e��g���$�H��F6��س�J=+'��Q���CE@SX״DUs�$�F"����.T���2 ��n�(E�Cл��e�J	~��x�>j�QN|�P�X�[k_��hS�~,H�";���Lj���7&��*���޶��
������|��>�F�e2m6��.�x���� ����R��P�<�iC�9՗�$:�匵��o ڭ�z���Xqh��kX\�%9WsjO8x-|������N��p:�j������c�\����'�g�NbM��4��fRi���x
�ݫy�T��FB�?��k�TNK�}t'˳��Y��+��Ue@����ԇ��Q��Lg�;g?�n�i��\�2.�{�������G�&uH\8J�(�qi7�R��A����|)��7F� e�fˀ���X����₉��B	��Q���U�Klx�#������sW����.Ra���� ����tH�N�mH�;J3��� z&=g���
Y��"4���F"(q ����Lm���{\��=��_'��Q�#�8��k�W�yVΛ�e��T�^;��Td����q=u�e�<OE�h��/[3��ǮŤ��	: Q{7�Ό~��7���"UbЅ�nƓB��:ۊ=/�q+Ì��FI['���'1�$����=��d^���$��M���hO�����:cэ���yHmf�6��I��s.���/��{��q����$����7���q�߂�������� ^�ѕm���w���^�m�^AGJMwO���zQ���9g?�&7�k��>��}\��\�q�'�gl0Qҕ�����ޒ��Aa�Z�b�|s����x.ńP g4J�΁�Sh9�	;����Ȇe����S��ė�_����F�9��qΝ��ܳ��U/�n�9�_B��柆�3/�1:ˡ�ԯ'���[�6��Ұl_3Op���a�w��,�CC�H���l�垑l�e僐�遼$v|�r!�>G΄]�5>��ǯgP����
(�o���؍�}���z��kfVѠ���z��rˈ�C�U�܍�g潯������gN�G�FZI�Q����a���_����MP�1�ʱ���gO�C��L1�'��ܟ�W� @E�:�d����/z���	�,�Ñ���"����4Y��7Ɉ^q��)W��D_ڡ�k�������� .7ٯw�n�eԜ�vN�g$��j�d7�o�R�L벌���8��37��~6J�Jiy�	�oi�������:n[�������8�,.S�"�.Ƕ�t0T��t�[[�<apc]�zI�M���jT�%@T��,&5���cbr�@����5r nQܴ/ўJV:/�o;%)A:�E��7����8ݔډ�#�<[�-5�>8��%��B�G_��&���5a��w��7בK�,���ķ;*��)�a
Br�*:u�ψ�����I�m�Ϯۅ�9�t� �?���;�/�>@��kL(����'���~����^�vd�N-M<�ˉե�b{�Q��d�!g7�R���� �O9g�c(aؙ�(�蝎��Ҿ����l:OC_�R�3e߽<j�8O����hD=1�U�K1�]����n����{�ĝ�sV���$D��Wګ��O`�[ä6�Ax'���V�#�u�p��1B�^f�����8��[�n����\�	��.�v����9�x��T���$l ���#���{隝SYSS�������O��7����j���,�AԯƵ�v�|R3@�ߟ�t�nB��;N^��2��箑.�uK����2f
�%�	O��d�b��I�<O�|��1����MY�J�����ƣ���R�?�a�l\kk�0rY`Əp_\G�j���e,$<b�FXS>(�b��#�
���dY�MD5�z���ڶ��ԍ+0�$x���쪎f�& t�Tp�jq�tNq�U�|�~ݍ��b�x��
H�z3ٲa�P2��Ap	�FI�fw�(L靳��� O5{���I`�Ϥ�]h�f%��o|˗���2we.��o&���ns�L2�S+x���#m%˷cJe��E��Мz�	V��_����OH�[/��������lީ,D|��5��?�@r�v9oF���Zui�m��)>�3s�b����wT��L��R�3l��4�3iSo�C�ڍ�?S�D����O·��G�pxW�N{-C���r^��h���T�v1I>���̪0#��S%b^9:���j|R��J;��XJH R}<9e�sH;��qx�1��+��z`3A��I�Hm�Ƅo�q,߲9�ف�����Ǘ����*y�<�����H��aZآ�����bSD����=�p�ap�3�&bI�]~f젮����	/�{|$���M�8�˩�6��Y�sW�X�-c�a3�W�v����JV�#�xR��g&�y�w\�m35��!�������d�SS�e� v�����)Gs�+`S�o\��kؽ� k)��B�������V��`���8u�͇�Hh޸�s��j%����{[w]L]Ê�:t�3R�f�e�b���IÏ���w�M�kR-�b��WZ��C3g���k����|bn�[�hŔ�}a?�E���+5�����=;
L]+�V�/���c��G-m|����4<K��r.͙�]�a�w��}�#��giۿU�Z����Up6�wȷ�U#����t�S�}�q��	�ɻ���)�T$,�pi}�p <(����v�>s������@��v2.��V����k�RƉ�+}ry
8������sl�l�e*�E�c���l���3��ޤ��' �㛻B���jA�i��rQ�j�ѯf��B�ʈ�|�6]�l��$qj���@�Y��Q&;"�;B�u��		�z���W�6-Vq<���	��Z��Ĵ ��Df�G3���"j%fR����ߺR���`",�-��S_�b�Z��Q���Tl�6n�Q �N�����k�,��EJ�9����ݻ�{>�T�pD���k1L��b��nlJ
�L�c׾��׌�A0p�c#�s�<�F�$/�Y�"e��g2�����Kے� ��~ц"�o�ʂ7NH��.T��?WRB�[\�#V,�{�Y6^S_���{�
�
2^8�Y4��a�����ZT��V���]q��0�,�w���;W&�\�i��A	���5�Q��L\��)�h�V�qG���_��S���YYc( �n-}���~t������/, F  ���_(��;t�������
�ZB�D�t�����,qxwב�j���M�d����:��. ��h�~_[�@X�:��{_$>$b�Gq"�Y����H����V ���G���q���
��K�~���	^����wm~����֚��f$�W��>�Wv��j��2�3�
��O���<�p�WA��P����ajw*���EQ�})�#�X�H��%���@�j�zG���2��7-u����e��] �R�~L5\�Ą������E]g�I9��b�ŕ�]����u�"�ثE�}Jx߷(JM��W�|�D�e4q>RS��V� ]�8�.�݋�}ٽ=�z�Y� ���v�I)���,���}6d��Ը��}-)Q�k��)0<&�����3��~��� �;wy�Ѽ�K�0� �;�J��kSGm�'�+y�R�c��66�
���w@;���~s�T��c� �"=7n��Ԛ"TR�g�z�nk.��$�����V������/���o�Ik�<��ں���z"���F��M�FפH�D���j��k	L^����:T���j�2p���w�.(醑�L7�o5]�� "�m�w���E��������d�X�^�,����� y$�9]�IK�˥��֘�V{���-�ʇ\K�9+��`��/N�Ŕ����W�B��SJ³�t�!ӷ�?��XU��T�_�7�=;b���C2�`��\1����Z��Y�d���,�1�c1�Su7�(�$}f%]����ŬgE�%��7q�؜���h@,!O�)R!�阔�9����w��4��\���	9���2�k��3;�!t%(�s?��?����Q2��p&3�K�'�K�������U&w@Jj�H>#_�k��crF[�_o���k}�&��J�Ym��(�������n��Lg��b1�8���-����^W��/I�I�# ��'=�/��\��5iq�{:O֮\�����D�	H�:�V�������]�{�8�Þ0u�4�vl������)�X�$���ޖ�~��xظ&6�]%��^ʹ�z��"`��'[R�t;�T�D��GmI�:7�>��U�����K�[�)�Wj��2���k��.%����h��=�%��Iq����5��n;m�Y�=�2a�5l��t:IDB��{�r�ڂ���%P�5o��;�Bs��-�M��p���F��K!S5�J�t�r1|7@2�{�^���Q�f>�)���?N�'	TK�o7�)�Sҋ`x�D�*�2I��+71���O����m���M��6������+}O��]��qqE�{��ќmyJQjj	�<X�.D-K�A���?�"<�ƄXJ���V�C];���$;����C^j�Q̠.�1�N��kN�w��~`%�ვ������̹u�q�iՏJ�R�N<��&��t�mm
>�2K�[59����g�\R6��u�����qwI�耐�[ڢ�Ð� ׬�e�i[}7Zf�����uq����!e`�Uu��G�+'ia\%�u`�
���]SR���]2G����#��x6�Xd�H�ՅP}�J�&Y�9Q��\:��sXT��'��+64���
g˜��s�a�+��}���7S��0�Z�)�U���U�
Mk�3С��۸ӹW�a'u��jV��7�Jb��'k�H����E��Z$^�f�Ρwgc�N!��OԔ��8�P(zk7�SK�4A�tz�j��^�����(�&�Κ'�=?�Q�s��&�\����=k6fpŜe{)������GX�2���۽�`�ݺ�v^��h�\x���,HT�W�n
��Wh�7��J̃(˥t��[ߗ]���g�����_[��:o&��=���4^4���f_Q�W��=�=!���r���K_��&�yYi��Am�~OeݲĖ������"�n�Xx�St%�)T�;�R�A*�:%��-�����=%���/K��ҁ �џ��w��Ȁ��}?��V�H���~�k��o�v#])����r����a�|�|���j�g��~WR�ɂO���j'`_���)�]���_�\5]`YOW����Wl#�����U��z�Rp����P=�Y��<�g��s��8zzq�T�C �+�;^ւ��˪%��֣Ko���:x��GrF�
�8�3�g��+�C��G��pC�� |���>���ݮ8�姢��x��yc�݀U4޴�e��[�)m���Pw�k
;�)�(��|�*&TX��8!��7Q�X�ղ��{��HZ��D�`隿qs{a�Z>_N.�_-�7�F_��7����鎋�a��O'�0:�ޱ��O�T�}9�zU����ζ��5�ӻ�肒�����^����`Tr]!������d+��AN����bΟ���>��=�vw�O�\ETHWf����q�ØJ�IG2u�pI���K��n�;��[�޹Q�������iEќ���E��]��!Ն���H�`R�ڧ^���p0�ьqeVX��z��g��H|�]��֙�!� ��f�;6O��)`{.m�=�Ad0�K�W�JM��ZK{~�7�+����c]S�B1��U;�]����W%�����+b]��z����/�����ӯ���m><E�Z�!�J0��N^[��p1�U�U	�����U�ϴ�y�m�"��C���"���Y�A#��G�T�΅ZT�P@B!����I�*�y�]e���i����~�n(�Z�v�F�
6�&��<8h'�53Vi�jh^Cn\3�<��U��r|��Bb��+^L4�9�;�z��C�M(�ZiR/������~�FmO^��c#�̵6t7l\��&�z�h�������W��;�}��Tm��Ш�4�\� {��KG	�iF���2��l*n
����%������eD���jO��R�`Ѐ(޵��	Z�Lx�ж޸t���ؼH� ��f�.Ң�MM���EG������y�V�p�#�?�/����OcJ���ɢC~K�W�*�KKߟu��������Z�l����v�]Py�\�BX�؏!�G��%�ɛ�U&+�T	p��ޯ�M��,��c�Ko5F�������C����!bw6�x�X�q���*Eˍ<����q0@�>�Y�;��a!}��.�ϚMAϊ}E�{޶�l�{��b��˛�R���a���A�5����Uܛ� ޞY���^i�m8c@��Њ�����Ot�z�T�)��&�2O��&=.��T��zA�Q3Ke2�Z�")�m%cri��%�V�د�+E�nZ��3&�P�
�n\w����3�_��z-Y~i<�|����xY�-볇IiNO�#1�8�<�p�:��C�7v�x���,v��Z�F�ׂo֛��:�W�Ԍ��<qf"�UD~�?���n�
��{GR���)t�&��f��U-A�R���;̈́7�
v��]�᥶��y��.�qgs|U�y(���s~��D��ſV��v�M�՝���y��C������^�H,�}Q��Ϋ<���FY.㺶��GUT��z_mk�#��{�4�����fyI�-df���O�(�W�O��V����b6咜9۩ӽ�S�$LST��@�霮�Z��Aq{�x�ϦYL����������q	Z�     