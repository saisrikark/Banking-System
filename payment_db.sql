DROP DATABASE payment;
CREATE DATABASE payment;

\c payment
--KEEPING LOGIN INFO SEPERATE FROM USERS AND MERCHANTS INFO
/*
DROP TABLE C2B_TRANSX_INFO;
DROP TABLE B2B_TRANSX_INFO;
DROP TABLE P2P_TRANSX_INFO;
DROP TABLE LENDING_INFO;
DROP TABLE FUNDS_TRANSFER_DETAILS;
DROP TABLE MERCHANT;
DROP TABLE CREDIT_RATING;
DROP TABLE USER_;
DROP TABLE LOGIN_INFO;
*/
CREATE TABLE LOGIN_INFO( 
	EMAIL_ID VARCHAR(30) NOT NULL UNIQUE,
	PASSWORD VARCHAR(30) NOT NULL, --check (password like '%[0-9]%' and password like '%[A-Z]%' and password like '%[!@#$%a^&*()-_+=.,;:'"`~]%' and len(password) >= 8),
	USER_NICK_NAME VARCHAR(20) NOT NULL UNIQUE,
	PRIMARY KEY(EMAIL_ID)
);

CREATE TABLE BANK_DETAIL(
	--FT_ID INT NOT NULL,
	ACCOUNT VARCHAR(30) NOT NULL UNIQUE CHECK (length(ACCOUNT) = 10),
	BANK_IFSC_CODE VARCHAR(30) NOT NULL CHECK (length(BANK_IFSC_CODE) = 11),
	--AMOUNT FLOAT NOT NULL,
	--TRANSX_FEE FLOAT NOT NULL,
	CUST_TYPE VARCHAR(30) NOT NULL ,
	--FOREIGN KEY(CUST_ID) REFERENCES LOGIN_INFO(CUST_ID) ON DELETE CASCADE,
	PRIMARY KEY(ACCOUNT)
);

CREATE TABLE USER_(
	USER_ID VARCHAR(10) NOT NULL UNIQUE CHECK (length(USER_ID) = 5),
	USER_NAME VARCHAR(30) NOT NULL UNIQUE,
	ACCOUNT VARCHAR(30) NOT NULL UNIQUE CHECK (length(ACCOUNT) = 10),
	EMAIL_ID VARCHAR(40) NOT NULL UNIQUE,
	PHONE_NO VARCHAR(10) NOT NULL UNIQUE CHECK (length(PHONE_NO) = 10),
	BALANCE FLOAT NOT NULL CHECK (BALANCE >= 0.0),
	STREET_ADDR VARCHAR(40) NOT NULL,
	CITY VARCHAR(20) NOT NULL,
	STATE VARCHAR(15) NOT NULL, 
	PRIMARY KEY(USER_ID),
	--FOREIGN KEY(USER_ID) REFERENCES LOGIN_INFO(CUST_ID) ON DELETE CASCADE
	FOREIGN KEY(EMAIL_ID) REFERENCES LOGIN_INFO(EMAIL_ID),
	FOREIGN KEY(ACCOUNT) REFERENCES BANK_DETAIL(ACCOUNT)
 	--CREDIT RATING IS PRIVILEDGED 
	--INFO AND IS KEPT IN A SEPERATE TABLE
);


CREATE TABLE CREDIT_RATING(
	USER_ID VARCHAR(10) NOT NULL UNIQUE CHECK (length(USER_ID) = 5),
	CRISIL_SCORE FLOAT NOT NULL,
	CIBIL_SCORE FLOAT NOT NULL,
	ICRA_SCORE FLOAT NOT NULL,
	FOREIGN KEY(USER_ID) REFERENCES USER_(USER_ID) ON DELETE CASCADE
);

CREATE TABLE MERCHANT(
	MERCH_ID VARCHAR(10) NOT NULL UNIQUE CHECK (length(MERCH_ID) = 5),
	MERCH_NAME VARCHAR(30) NOT NULL UNIQUE,
	PHONE_NO VARCHAR(10) NOT NULL UNIQUE CHECK (length(PHONE_NO) = 10),
	ACCOUNT VARCHAR(30) NOT NULL UNIQUE CHECK (length(ACCOUNT) = 10),
	STREET_ADDR VARCHAR(40) NOT NULL,
	CITY VARCHAR(20) NOT NULL,
	STATE VARCHAR(15) NOT NULL,
	EMAIL_ID VARCHAR(40) NOT NULL UNIQUE,
	BALANCE FLOAT NOT NULL CHECK (BALANCE >= 0.0),
	PRIMARY KEY(MERCH_ID),
	FOREIGN KEY(EMAIL_ID) REFERENCES LOGIN_INFO(EMAIL_ID),
	FOREIGN KEY(ACCOUNT) REFERENCES BANK_DETAIL(ACCOUNT)
	--FOREIGN KEY(MERCH_ID) REFERENCES LOGIN_INFO(CUST_ID) ON DELETE CASCADE
	--DETAILED TAX INFO IS KEPT IN SEPERATE TABLE
	--OR WE COULD GENERATE ONSPOT WITH TRANSACTIONS
	--CHECK BALANCE >= 0
);


--we could also link the foreign keys to bank_detail
CREATE TABLE TRANSFER_USER_INFO(
	ID INT NOT NULL UNIQUE,
	ACCOUNT VARCHAR(30) NOT NULL CHECK (length(ACCOUNT) = 10),
	AMOUNT FLOAT NOT NULL,
	CUST_ID VARCHAR(10) NOT NULL CHECK (length(CUST_ID) = 5),
	TYPE VARCHAR(10),
	FOREIGN KEY(ACCOUNT) REFERENCES USER_(ACCOUNT) ON DELETE CASCADE,
	PRIMARY KEY(ID)
);

--BANK USER TRANSACTION BALANCE UPDATE
CREATE FUNCTION bank_user_transx() RETURNS trigger AS
$BODY$
	BEGIN
		IF (NEW.TYPE = 'CREDIT') THEN
		UPDATE USER_
		SET BALANCE = BALANCE + NEW.AMOUNT
		WHERE USER_.USER_ID = NEW.CUST_ID;
		ELSE 
		UPDATE USER_
		SET BALANCE = BALANCE - NEW.AMOUNT
		WHERE USER_.USER_ID = NEW.CUST_ID AND BALANCE >= NEW.AMOUNT;
		END IF ;
		RETURN NEW;
	END;
$BODY$
LANGUAGE plpgsql VOLATILE
  COST 100;

CREATE TRIGGER BANK_USER_TRANSX_UPDATE
BEFORE INSERT ON TRANSFER_USER_INFO
FOR EACH ROW
EXECUTE PROCEDURE bank_user_transx();


CREATE TABLE TRANSFER_MERCH_INFO(
	ID INT NOT NULL UNIQUE,
	ACCOUNT VARCHAR(30) NOT NULL,
	AMOUNT FLOAT NOT NULL,
	CUST_ID VARCHAR(10) NOT NULL,
	TYPE VARCHAR(10),
	FOREIGN KEY(ACCOUNT) REFERENCES MERCHANT(ACCOUNT) ON DELETE CASCADE,
	FOREIGN KEY(CUST_ID) REFERENCES MERCHANT(MERCH_ID) ON DELETE CASCADE,
	PRIMARY KEY(ID)	
);

--BANK USER TRANSACTION BALANCE UPDATE
CREATE FUNCTION bank_merch_transx() RETURNS trigger AS
$BODY$
	BEGIN
		IF (NEW.TYPE = 'CREDIT') THEN
		UPDATE MERCHANT
		SET BALANCE = BALANCE + NEW.AMOUNT
		WHERE MERCHANT.MERCH_ID = NEW.CUST_ID;
		ELSE 
		UPDATE MERCHANT
		SET BALANCE = BALANCE - NEW.AMOUNT
		WHERE MERCHANT.MERCH_ID = NEW.CUST_ID AND BALANCE >= NEW.AMOUNT;
		END IF ;
		RETURN NEW;
	END;
$BODY$
LANGUAGE plpgsql VOLATILE
  COST 100;

CREATE TRIGGER BANK_MERCH_TRANSX_UPDATE
BEFORE INSERT ON TRANSFER_MERCH_INFO
FOR EACH ROW
EXECUTE PROCEDURE bank_merch_transx();



CREATE TABLE LENDING_INFO(
	PRINCIPAL_AMOUNT INT NOT NULL,
	DATE_OF_PAY DATE NOT NULL,
	DATE_OF_LOAN DATE NOT NULL,
	INTEREST_RATE FLOAT CHECK (INTEREST_RATE <= 20.0),
	LEND_ID INT NOT NULL,
	BORROWER_ID VARCHAR(10) NOT NULL,
	LENDER_ID VARCHAR(10) NOT NULL,
	FOREIGN KEY(LENDER_ID) REFERENCES USER_(USER_ID) ON DELETE CASCADE,
	FOREIGN KEY(BORROWER_ID) REFERENCES USER_(USER_ID) ON DELETE CASCADE,
	PRIMARY KEY(LEND_ID)
);

--LENDING INFO
CREATE FUNCTION lend_transx() RETURNS trigger AS
$BODY$
	BEGIN
	IF EXISTS(SELECT * FROM USER_ WHERE USER_.USER_ID = NEW.LENDER_ID AND USER_.BALANCE> NEW.PRINCIPAL_AMOUNT) THEN
		UPDATE USER_
		SET BALANCE = BALANCE - NEW.PRINCIPAL_AMOUNT
		WHERE USER_.USER_ID = NEW.LENDER_ID AND BALANCE >= NEW.PRINCIPAL_AMOUNT;
		UPDATE USER_
		SET BALANCE = BALANCE + NEW.PRINCIPAL_AMOUNT
		WHERE USER_.USER_ID = NEW.BORROWER_ID;
		RETURN NEW;
	END IF;
	END;
$BODY$
LANGUAGE plpgsql VOLATILE
  COST 100;

CREATE TRIGGER USER_TRANSX_UPDATE
BEFORE INSERT ON LENDING_INFO
FOR EACH ROW
EXECUTE PROCEDURE lend_transx();


CREATE TABLE P2P_TRANSX_INFO(
	TRANSX_ID INT NOT NULL,
	AMOUNT FLOAT NOT NULL,
	RECEIVEE_ID VARCHAR(10) NOT NULL,
	PAYEE_ID VARCHAR(10) NOT NULL,
	-- LETS NOT KEEP FOR P2P TRANSX_FEE FLOAT NOT NULL,
	FOREIGN KEY(PAYEE_ID) REFERENCES USER_(USER_ID) ON DELETE CASCADE,
	FOREIGN KEY(RECEIVEE_ID) REFERENCES USER_(USER_ID) ON DELETE CASCADE,
	PRIMARY KEY(TRANSX_ID)
);

CREATE TABLE C2B_TRANSX_INFO(
	TRANSX_ID INT NOT NULL,
	BILL_VALUE FLOAT NOT NULL,
	TAXES FLOAT NOT NULL,
	TRANSX_FEE FLOAT NOT NULL,
	RECEIVEE_ID VARCHAR(10) NOT NULL,
	PAYEE_ID VARCHAR(10) NOT NULL,

	FOREIGN KEY(PAYEE_ID) REFERENCES USER_(USER_ID) ON DELETE CASCADE,
	FOREIGN KEY(RECEIVEE_ID) REFERENCES MERCHANT(MERCH_ID) ON DELETE CASCADE,
	PRIMARY KEY(TRANSX_ID)
);

CREATE TABLE B2B_TRANSX_INFO(
	TRANSX_ID INT NOT NULL,
	BILL_VALUE FLOAT NOT NULL,
	TAXES FLOAT NOT NULL,
	TRANSX_FEE FLOAT NOT NULL,
	RECEIVEE_ID VARCHAR(10) NOT NULL,
	PAYEE_ID VARCHAR(10) NOT NULL,
	FOREIGN KEY(PAYEE_ID) REFERENCES MERCHANT(MERCH_ID) ON DELETE CASCADE,
	FOREIGN KEY(RECEIVEE_ID) REFERENCES MERCHANT(MERCH_ID) ON DELETE CASCADE,
	PRIMARY KEY(TRANSX_ID)
);
--P2P TRANSACTION BALANCE UPDATE
CREATE FUNCTION user_transx() RETURNS trigger AS
$BODY$
	BEGIN
	IF EXISTS(SELECT * FROM USER_ WHERE USER_.USER_ID = NEW.PAYEE_ID AND USER_.BALANCE> NEW.AMOUNT) THEN
		UPDATE USER_
		SET BALANCE = BALANCE - NEW.AMOUNT
		WHERE USER_.USER_ID = NEW.PAYEE_ID AND BALANCE >= NEW.AMOUNT;
		UPDATE USER_
		SET BALANCE = BALANCE + NEW.AMOUNT
		WHERE USER_.USER_ID = NEW.RECEIVEE_ID;
		RETURN NEW;
	END IF;
	END;
$BODY$
LANGUAGE plpgsql VOLATILE
  COST 100;

CREATE TRIGGER USER_TRANSX_UPDATE
BEFORE INSERT ON P2P_TRANSX_INFO
FOR EACH ROW
EXECUTE PROCEDURE user_transx();
--B2B TRANSACTION BALANCE UPDATE
CREATE FUNCTION merch_transx() RETURNS trigger AS
$BODY$
	BEGIN
	IF EXISTS(SELECT * FROM MERCHANT WHERE MERCH_ID = NEW.PAYEE_ID AND BALANCE > NEW.BILL_VALUE + NEW.TAXES + NEW.TRANSX_FEE) THEN
		UPDATE MERCHANT
		SET BALANCE = BALANCE - NEW.BILL_VALUE - NEW.TAXES - NEW.TRANSX_FEE
		WHERE MERCHANT.MERCH_ID = NEW.PAYEE_ID AND BALANCE >= NEW.BILL_VALUE + NEW.TAXES + NEW.TRANSX_FEE;
		UPDATE MERCHANT
		SET BALANCE = BALANCE + NEW.BILL_VALUE
		WHERE MERCHANT.MERCH_ID = NEW.RECEIVEE_ID;
		RETURN NEW;
	END IF;
	END;
$BODY$
LANGUAGE plpgsql VOLATILE
  COST 100;

CREATE TRIGGER MERCH_TRANSX_UPDATE
BEFORE INSERT ON B2B_TRANSX_INFO
FOR EACH ROW
EXECUTE PROCEDURE merch_transx();



INSERT INTO LOGIN_INFO VALUES('shekar@gmail.com', 'shek123', 'shekshek');
INSERT INTO LOGIN_INFO VALUES('vishal@yahoo.com', 'vishal', 'vish25Mar');
INSERT INTO LOGIN_INFO VALUES('shankar@hotmail.com', 'shank', 'shankar123');
INSERT INTO LOGIN_INFO VALUES('sailesh@hotmail.com', 'sail', 'sail123');
INSERT INTO LOGIN_INFO VALUES('madhav@aol.com', 'mad', '108mad');
INSERT INTO LOGIN_INFO VALUES('keshav@gmail.com', 'kesh', 'keshav108');
INSERT INTO LOGIN_INFO VALUES('saahitya.e@gmail.com', 'sas', 'saahi');
INSERT INTO LOGIN_INFO VALUES('sankarshana@gmail.com', 's123', 'sanky');
INSERT INTO LOGIN_INFO VALUES('srikar@yahoo.com', 'sri', 'srikar');
INSERT INTO LOGIN_INFO VALUES('rohan.t@hotmail.com', '123456', 'rohan');
INSERT INTO LOGIN_INFO VALUES('shashank.b@gmail.com', 'shash', 'algorithms');

INSERT INTO LOGIN_INFO VALUES('a2b@yahoo.com', 'admin', 'admin');
INSERT INTO LOGIN_INFO VALUES('kiran_suppliers@hotmail.com', 'password', 'kiran');
INSERT INTO LOGIN_INFO VALUES('pesu@hotmail.com', 'pesu', 'pesu');
INSERT INTO LOGIN_INFO VALUES('walmart@hotmail.com', 'wal123', 'walmart');
INSERT INTO LOGIN_INFO VALUES('shoppersave@gmail.com', 'shop456', 'shoppersave');
INSERT INTO LOGIN_INFO VALUES('cello@yahoo.com', 'cello789', 'cello');
INSERT INTO LOGIN_INFO VALUES('nilgiris@hotmail.com', 'nil123', 'admin123');
INSERT INTO LOGIN_INFO VALUES('maiyas@hotmail.com', 'Ilovedosa', 'MrMaiya');
INSERT INTO LOGIN_INFO VALUES('faber_castle_india@gmail.com', 'fb123', 'faber_castle');
INSERT INTO LOGIN_INFO VALUES('farmfresh@yahoo.com', 'farmfresh789', 'farmfresh');
INSERT INTO LOGIN_INFO VALUES('itc_stationary@gmail.com', 'itc456', 'itc');

INSERT INTO BANK_DETAIL VALUES('12345678AB', 'SBIN0000058', 'Merchant');
INSERT INTO BANK_DETAIL VALUES('12345678CD', 'SBIN0000058', 'Merchant');
INSERT INTO BANK_DETAIL VALUES('12345679EF', 'SBIN0000059', 'Merchant');
INSERT INTO BANK_DETAIL VALUES('12345698GH', 'SBIN0000080', 'Merchant');
INSERT INTO BANK_DETAIL VALUES('12345698IJ', 'SBIN0000056', 'Merchant');
INSERT INTO BANK_DETAIL VALUES('12345698KL', 'SBIN0000123', 'Merchant');
INSERT INTO BANK_DETAIL VALUES('12344454OP', 'SBIN0000123', 'Merchant');
INSERT INTO BANK_DETAIL VALUES('12322300IT', 'SBIN0000058', 'Merchant');
INSERT INTO BANK_DETAIL VALUES('12345698PQ', 'SBIN0000060', 'Merchant');
INSERT INTO BANK_DETAIL VALUES('12345602WE', 'SBIN0000021', 'Merchant');
INSERT INTO BANK_DETAIL VALUES('12344554UR', 'SBIN0000021', 'Merchant');

INSERT INTO BANK_DETAIL VALUES('12345612XY', 'SBIN0000101', 'User');
INSERT INTO BANK_DETAIL VALUES('12345667IO', 'SBIN0000102', 'User');
INSERT INTO BANK_DETAIL VALUES('12345643PO', 'SBIN0000101', 'User');
INSERT INTO BANK_DETAIL VALUES('54353454BY', 'SBIN0000104', 'User');
INSERT INTO BANK_DETAIL VALUES('34756385NM', 'SBIN0000103', 'User');
INSERT INTO BANK_DETAIL VALUES('89754358TY', 'SBIN0000103', 'User');
INSERT INTO BANK_DETAIL VALUES('34875356CV', 'SBIN0000104', 'User');
--INSERT INTO BANK_DETAIL VALUES('98765432QW', 'SBIN0000101', 'User');
INSERT INTO BANK_DETAIL VALUES('98765432QW', 'SBIN0000058', 'User');

INSERT INTO BANK_DETAIL VALUES('23423344BG', 'SBIN0000103', 'User');
INSERT INTO BANK_DETAIL VALUES('32134567UI', 'SBIN0000115', 'User');
INSERT INTO BANK_DETAIL VALUES('09482478OP', 'SBIN0000112', 'User');

INSERT INTO USER_ VALUES('12345', 'Shekar', '12345612XY', 'shekar@gmail.com', '9845631242', 1045, '123-Brigade Millenium Apt', 'Bangalore', 'Karnataka');
INSERT INTO USER_ VALUES('23456', 'Vishal', '12345667IO', 'vishal@yahoo.com', '9845314543', 530, '456-Brigade Millenium Apt', 'Mumbai', 'Maharashtra');
INSERT INTO USER_ VALUES('34567', 'Shankar', '12345643PO', 'shankar@hotmail.com', '9801486406', 2500, '789-Brigade Millenium Apt', 'Bangalore', 'Karnataka');
INSERT INTO USER_ VALUES('45678', 'Sailesh', '54353454BY', 'sailesh@hotmail.com', '9999999999', 120000, '789-Brigade Millenium Apt', 'Delhi', 'NCR');
INSERT INTO USER_ VALUES('56789', 'Madhav',  '34756385NM', 'madhav@aol.com', '9683434571', 1000, '789-Brigade Millenium Apt', 'Bangalore', 'Karnataka');
INSERT INTO USER_ VALUES('67890', 'Keshav',  '89754358TY', 'keshav@gmail.com', '9878775611', 2500, '789-Brigade Millenium Apt', 'Chennai', 'Tamil Nadu');
INSERT INTO USER_ VALUES('78901', 'Saahitya','34875356CV', 'saahitya.e@gmail.com', '9923143240', 2500, '098-Brigade Millenium Apt', 'Bangalore', 'Karnataka');
INSERT INTO USER_ VALUES('89012', 'Sankarshana', '98765432QW', 'sankarshana@gmail.com', '9189753451', 7983, '#789-NagarBhavi', 'Bangalore', 'Karnataka');
INSERT INTO USER_ VALUES('90123', 'Srikar',  '23423344BG', 'srikar@yahoo.com', '9124367819', 10000, '#123 HSR Layout', 'Bangalore', 'Karnataka');
INSERT INTO USER_ VALUES('98765', 'Rohan',   '32134567UI', 'rohan.t@hotmail.com', '9544561799', 2500, '#678 C.R Pet', 'Bangalore', 'Karnataka');
INSERT INTO USER_ VALUES('48934', 'Shashank','09482478OP', 'shashank.b@gmail.com', '9053451312', 12349, '#789 Main Road', 'Davangere', 'Karnataka');
--select * from user_;
INSERT INTO MERCHANT VALUES('98765', 'a2b', '9067981230', '12345678AB', '123-JP Nagar', 'Bangalore', 'Karnataka', 'a2b@yahoo.com', 10450);
INSERT INTO MERCHANT VALUES('87654', 'kiran_supp', '9567340990', '12345678CD', '456-JP Nagar', 'Bangalore', 'Karnataka', 'kiran_suppliers@hotmail.com', 9000);
INSERT INTO MERCHANT VALUES('87655', 'pesu', '9567340909', '12345679EF', '456-JayaNagar', 'Bangalore', 'Karnataka', 'pesu@hotmail.com', 900);
INSERT INTO MERCHANT VALUES('87656', 'walmart', '9567340912', '12345698GH', '256-JP Nagar', 'Bangalore', 'Karnataka', 'walmart@hotmail.com', 90000);
INSERT INTO MERCHANT VALUES('87657', 'ShopperSave', '9353434123', '12345698IJ', '012-JP Nagar', 'Bangalore', 'Karnataka', 'shoppersave@gmail.com', 2000);
INSERT INTO MERCHANT VALUES('87658', 'Cello', '9845512345', '12345698KL', '789-MG Road', 'Lucknow', 'UP', 'cello@yahoo.com', 90000);
INSERT INTO MERCHANT VALUES('87659', 'Nilgiris', '9123675091', '12344454OP', '456-JP Nagar', 'Bangalore', 'Karnataka', 'nilgiris@hotmail.com', 23450);
INSERT INTO MERCHANT VALUES('87660', 'Maiyas',   '9834234244', '12322300IT', '789-JayaNagar Nagar', 'Bangalore', 'Karnataka', 'maiyas@hotmail.com', 78945);
INSERT INTO MERCHANT VALUES('87661', 'Faber Castle', '9807572098', '12345698PQ', '#456 Bandra Road', 'Mumbai', 'MH', 'faber_castle_india@gmail.com', 79834);
INSERT INTO MERCHANT VALUES('87662', 'Farm Fresh', 	 '9023424445', '12345602WE', '#987 Red Hills', 'Ooty', 'TN', 'farmfresh@yahoo.com', 573443);
INSERT INTO MERCHANT VALUES('87663', 'ITC Stationary','9745353535', '12344554UR', '#456 MG Road', 'Bangalore', 'Karnataka', 'itc_stationary@gmail.com', 457343);

INSERT INTO CREDIT_RATING VALUES('12345', 683.78, 457.98, 707.98);
INSERT INTO CREDIT_RATING VALUES('23456', 798.12, 908.98, 234.56);
INSERT INTO CREDIT_RATING VALUES('34567', 567.09, 134.76, 987.99);
INSERT INTO CREDIT_RATING VALUES('45678', 345.90, 300.56, 365.56);
INSERT INTO CREDIT_RATING VALUES('56789', 567.09, 589.46, 598.99);
INSERT INTO CREDIT_RATING VALUES('67890', 243.09, 265.64, 265.34);
INSERT INTO CREDIT_RATING VALUES('78901', 965.09, 965.43, 987.00);
INSERT INTO CREDIT_RATING VALUES('89012', 845.09, 856.76, 900.99);
INSERT INTO CREDIT_RATING VALUES('90123', 134.09, 134.65, 165.45);
INSERT INTO CREDIT_RATING VALUES('98765', 845.09, 867.12, 876.12);
INSERT INTO CREDIT_RATING VALUES('48934', 587.45, 567.34, 584.44);

INSERT INTO TRANSFER_MERCH_INFO VALUES(1937,'12345678AB',8473.32,'98765','DEBIT');
INSERT INTO TRANSFER_MERCH_INFO VALUES(2912,'12345678CD',1273.32,'87654','CREDIT');
INSERT INTO TRANSFER_MERCH_INFO VALUES(2913,'12345679EF',120.00,'87655','CREBIT');
INSERT INTO TRANSFER_MERCH_INFO VALUES(2914,'12345698GH',730.30,'87656','CREDIT');
INSERT INTO TRANSFER_MERCH_INFO VALUES(2915,'12345698IJ',1000.45,'87657','CREBIT');
INSERT INTO TRANSFER_MERCH_INFO VALUES(2916,'12345698KL',500.20,'87658','CREDIT');
INSERT INTO TRANSFER_MERCH_INFO VALUES(2917,'12344454OP',1273.32,'87659','CREDIT');
INSERT INTO TRANSFER_MERCH_INFO VALUES(2918,'12322300IT',1273.32,'87660','CREDIT');
INSERT INTO TRANSFER_MERCH_INFO VALUES(2919,'12345698PQ',1273.32,'87661','CREDIT');
INSERT INTO TRANSFER_MERCH_INFO VALUES(2920,'12345602WE',1273.32,'87662','CREDIT');
INSERT INTO TRANSFER_MERCH_INFO VALUES(2921,'12344554UR',1273.32,'87663','CREDIT');

INSERT INTO TRANSFER_USER_INFO VALUES(9292,'12345612XY',3454.2,'12345','DEBIT');
INSERT INTO TRANSFER_USER_INFO VALUES(1984,'12345667IO',9932.2,'23456','CREDIT');
INSERT INTO TRANSFER_USER_INFO VALUES(1985,'12345643PO',9932.2,'34567','CREDIT');
INSERT INTO TRANSFER_USER_INFO VALUES(1986,'54353454BY',9932.2,'45678','CREDIT');
INSERT INTO TRANSFER_USER_INFO VALUES(1987,'34756385NM',9932.2,'56789','CREDIT');
INSERT INTO TRANSFER_USER_INFO VALUES(1988,'89754358TY',9932.2,'67890','CREDIT');
INSERT INTO TRANSFER_USER_INFO VALUES(1989,'34875356CV',9932.2,'78901','CREDIT');
INSERT INTO TRANSFER_USER_INFO VALUES(1990,'98765432QW',9932.2,'89012','CREDIT');
INSERT INTO TRANSFER_USER_INFO VALUES(1991,'23423344BG',9932.2,'90123','CREDIT');
INSERT INTO TRANSFER_USER_INFO VALUES(1992,'32134567UI',9932.2,'98765','CREDIT');
INSERT INTO TRANSFER_USER_INFO VALUES(1993,'09482478OP',9932.2,'48934','CREDIT');

INSERT INTO P2P_TRANSX_INFO VALUES(9472,100,'12345','34567');
INSERT INTO P2P_TRANSX_INFO VALUES(9473,200,'34567','23456');
INSERT INTO P2P_TRANSX_INFO VALUES(9474,300,'34567','67890');
INSERT INTO P2P_TRANSX_INFO VALUES(9475,400,'78901','34567');
INSERT INTO P2P_TRANSX_INFO VALUES(9476,400,'90123','56789');
INSERT INTO P2P_TRANSX_INFO VALUES(9477,500,'48934','56789');
INSERT INTO P2P_TRANSX_INFO VALUES(9478,3000,'89012','45678');
INSERT INTO P2P_TRANSX_INFO VALUES(9479,6000,'12345','45678');
INSERT INTO P2P_TRANSX_INFO VALUES(9480,1000,'90123','45678');
INSERT INTO P2P_TRANSX_INFO VALUES(9481,200,'89012','23456');
INSERT INTO P2P_TRANSX_INFO VALUES(94782,300,'56789','98765');


INSERT INTO B2B_TRANSX_INFO VALUES(9472,1000, 10, 10, '87655','87660');
INSERT INTO B2B_TRANSX_INFO VALUES(9473,2653.545, 26, 10, '87655','87654');
INSERT INTO B2B_TRANSX_INFO VALUES(9474,300, 3 , 10, '87663','87656');
INSERT INTO B2B_TRANSX_INFO VALUES(9475,4564.34, 45, 10, '87663','87657');
INSERT INTO B2B_TRANSX_INFO VALUES(9476,4012, 40, 10, '87663','87659');
INSERT INTO B2B_TRANSX_INFO VALUES(9477,8273.3, 82, 10, '87661','98765');
INSERT INTO B2B_TRANSX_INFO VALUES(9478,3424.23, 34, 10, '87661','87656');
INSERT INTO B2B_TRANSX_INFO VALUES(9479,2342.34, 23, 10, '87661','87657');
INSERT INTO B2B_TRANSX_INFO VALUES(9480,1233.3, 12, 10, '87661','87660');
INSERT INTO B2B_TRANSX_INFO VALUES(9481,1233.23, 12, 10, '87662','87660');
INSERT INTO B2B_TRANSX_INFO VALUES(94782,1243.23, 12, 10, '87662','98765');


INSERT INTO LENDING_INFO VALUES(1000, '2015-05-14', '2015-03-14', '10', 123, '78901', '45678');
INSERT INTO LENDING_INFO VALUES(2000, '2015-06-14', '2015-04-14', '10', 124, '89012', '45678');
INSERT INTO LENDING_INFO VALUES(3000, '2016-05-21', '2016-01-21', '10', 125, '12345', '45678');
INSERT INTO LENDING_INFO VALUES(60000, '2018-09-29', '2018-01-29', '10', 126, '89012', '45678');
INSERT INTO LENDING_INFO VALUES(2100, '2017-05-14', '2017-03-14', '10', 127, '23456', '45678');
INSERT INTO LENDING_INFO VALUES(1200, '2015-05-14', '2015-03-14', '10', 128, '34567', '45678');
INSERT INTO LENDING_INFO VALUES(332, '2016-05-14', '2016-03-14', '10', 129, '45678', '12345');
INSERT INTO LENDING_INFO VALUES(908, '2012-12-31', '2012-03-14', '10', 130, '48934', '12345');
INSERT INTO LENDING_INFO VALUES(792, '2012-05-23', '2012-03-23', '10', 131, '98765', '34567');
INSERT INTO LENDING_INFO VALUES(1232, '2018-05-14', '2018-03-14', '10', 132, '98765', '34567');
INSERT INTO LENDING_INFO VALUES(2567, '2017-05-14', '2017-03-14', '10', 133, '89012', '23456');
INSERT INTO P2P_TRANSX_INFO VALUES(94783,70000,'45678','89012');

INSERT INTO C2B_TRANSX_INFO VALUES(9472,1000, 10, 10, '87655','12345');
INSERT INTO C2B_TRANSX_INFO VALUES(9473,2653.545, 26, 10, '87655','34567');
INSERT INTO C2B_TRANSX_INFO VALUES(9474,300, 3 , 10, '87663','34567');
INSERT INTO C2B_TRANSX_INFO VALUES(9475,4564.34, 45, 10, '87663','78901');
INSERT INTO C2B_TRANSX_INFO VALUES(9476,4012, 40, 10, '87663','90123');
INSERT INTO C2B_TRANSX_INFO VALUES(9477,8273.3, 82, 10, '87661','48934');
INSERT INTO C2B_TRANSX_INFO VALUES(9478,3424.23, 34, 10, '87661','89012');
INSERT INTO C2B_TRANSX_INFO VALUES(9479,2342.34, 23, 10, '87661','12345');
INSERT INTO C2B_TRANSX_INFO VALUES(9480,1233.3, 12, 10, '87661','90123');
INSERT INTO C2B_TRANSX_INFO VALUES(9481,1233.23, 12, 10, '87662','89012');
INSERT INTO C2B_TRANSX_INFO VALUES(94782,1243.23, 12, 10, '87662','56789');

/*
SELECT * FROM LOGIN_INFO;
SELECT * FROM BANK_DETAIL;
SELECT * FROM MERCHANT;
SELECT * FROM CREDIT_RATING;
SELECT * FROM TRANSFER_MERCH_INFO;
SELECT * FROM TRANSFER_USER_INFO;
SELECT * FROM P2P_TRANSX_INFO;
SELECT * FROM USER_;
*/
/*INSERT INTO LENDING_INFO VALUES(amount,interval,date_loan,intrate,lend_id,borr_id,lender_id);
INSERT INTO C2B_TRANSX_INFO VALUES(7431,92545.12,);
INSERT INTO B2B_TRANSX_INFO VALUES();
*/
/*
SELECT AVG(AMOUNT)
FROM P2P_TRANSX_INFO
WHERE P2P_TRANSX_INFO.AMOUNT > 5000;
*/
--select * from user_;