CREATE OR REPLACE PROCEDURE LOAD_TO_RAW()
RETURNS VARCHAR(16777216)
LANGUAGE SQL
EXECUTE AS OWNER
AS 'BEGIN
  BEGIN TRANSACTION;
  
  COPY INTO raw_table 
  FROM @csv_stage
  FILE_FORMAT = (TYPE = ''csv'' RECORD_DELIMITER = ''\\n''
  FIELD_DELIMITER= '','' SKIP_HEADER = 1 empty_field_as_null = true FIELD_OPTIONALLY_ENCLOSED_BY = ''"'' ESCAPE_UNENCLOSED_FIELD = None );
  
  COMMIT;
  
  RETURN ''Finished creating stored procedures LOAD_TO_RAW'';
END';

CREATE OR REPLACE PROCEDURE INITIAL_LOAD_TO_COUNTRIES()
RETURNS VARCHAR(16777216)
LANGUAGE SQL
EXECUTE AS CALLER
AS 'BEGIN 

  BEGIN TRANSACTION;

  INSERT INTO COUNTRIES (AIRPORTCOUNTRYCODE, COUNTRYNAME)
  SELECT DISTINCT AIRPORTCOUNTRYCODE, COUNTRYNAME
  FROM raw_table
  WHERE COUNTRYNAME <> \'Venezuela\'
  ORDER BY AIRPORTCOUNTRYCODE;

  COMMIT;

  RETURN ''Finished creating stored procedures INITIAL_LOAD_TO_COUNTRIES'';
END';

CREATE OR REPLACE PROCEDURE INITIAL_LOAD_TO_CONTINENTS()
RETURNS VARCHAR(16777216)
LANGUAGE SQL
EXECUTE AS CALLER
AS 'BEGIN 

  BEGIN TRANSACTION;

  INSERT INTO CONTINENTS (AIRPORTCONTINENT, CONTINENTS)
  SELECT DISTINCT AIRPORTCONTINENT,CONTINENTS
  FROM raw_table;

  COMMIT;

  RETURN ''Finished creating stored procedures INITIAL_LOAD_TO_CONTINENTS'';
END';

CREATE OR REPLACE PROCEDURE INITIAL_LOAD_TO_AIRPORTS()
RETURNS VARCHAR(16777216)
LANGUAGE SQL
EXECUTE AS CALLER
AS 'BEGIN
    
  BEGIN TRANSACTION;

  INSERT INTO AIRPORTS (AIRPORTNAME, ARRIVALAIRPORT)
  SELECT AIRPORTNAME, ARRIVALAIRPORT
  FROM (
      SELECT AIRPORTNAME, ARRIVALAIRPORT,
            ROW_NUMBER() OVER(PARTITION BY AIRPORTNAME ORDER BY ARRIVALAIRPORT) AS rn
      FROM raw_table
  ) AS ranked
  WHERE rn = 1;

  COMMIT;

  RETURN ''Finished creating stored procedures INITIAL_LOAD_TO_AIRPORTS'';
END';

CREATE OR REPLACE PROCEDURE INITIAL_LOAD_TO_PASSENGERS()
RETURNS VARCHAR(16777216)
LANGUAGE SQL
EXECUTE AS CALLER
AS 'BEGIN

  BEGIN TRANSACTION;

  INSERT INTO PASSENGERS (PASSENGERCODE, FIRSTNAME, LASTNAME, GENDER, AGE, NATIONALITY, TICKETTYPE, PASSENGERSTATUS)
  SELECT DISTINCT PASSENGERCODE, FIRSTNAME, LASTNAME, GENDER, AGE, NATIONALITY, TICKETTYPE, PASSENGERSTATUS 
  FROM raw_table;

  COMMIT;

  RETURN ''Finished creating stored procedures INITIAL_LOAD_TO_PASSENGERS'';
END';

CREATE OR REPLACE PROCEDURE INITIAL_LOAD_TO_PLANES()
RETURNS VARCHAR(16777216)
LANGUAGE SQL
EXECUTE AS CALLER
AS 'BEGIN
  BEGIN TRANSACTION;

  INSERT INTO PLANES (DEPARTUREDATE, PILOTNAME, FLIGHTSTATUS, PASSENGERID, AIRPORTID, COUNTRYID, CONTINENTID)
  SELECT DISTINCT   DEPARTUREDATE, PILOTNAME, FLIGHTSTATUS, PASSENGERS.PASSENGERID, AIRPORTS.AIRPORTID, COUNTRIES.COUNTRYID, CONTINENTS.CONTINENTID FROM raw_table
  JOIN AIRPORTS ON AIRPORTS.AIRPORTNAME = raw_table.AIRPORTNAME
  JOIN PASSENGERS ON PASSENGERS.PASSENGERCODE = raw_table.PASSENGERCODE
  JOIN COUNTRIES ON COUNTRIES.AIRPORTCOUNTRYCODE = raw_table.AIRPORTCOUNTRYCODE
  JOIN CONTINENTS ON CONTINENTS.AIRPORTCONTINENT = raw_table.AIRPORTCONTINENT;

  COMMIT;

  RETURN ''Finished creating stored procedures INITIAL_LOAD_TO_PLANES'';
END';


CREATE OR REPLACE PROCEDURE INCREMENTAL_LOAD()
RETURNS VARCHAR(16777216)
LANGUAGE SQL
EXECUTE AS CALLER
AS 'BEGIN
  BEGIN TRANSACTION;

    BEGIN TRANSACTION;

  MERGE INTO PASSENGERS as T
  USING (SELECT *
  FROM raw_table_stream) AS S
  ON T.PASSENGERCODE = S.PASSENGERCODE
  WHEN matched AND S.metadata$action = \'INSERT\' AND S.metadata$isupdate
  THEN
  UPDATE SET T.FIRSTNAME = S.FIRSTNAME, T.LASTNAME = S.LASTNAME,T.GENDER = S.GENDER, 
  T.AGE = S.AGE, T.NATIONALITY = S.NATIONALITY, T.TICKETTYPE = S.TICKETTYPE, T.PASSENGERSTATUS=S.PASSENGERSTATUS
  WHEN matched
  AND S.metadata$action = \'DELETE\' THEN DELETE
  WHEN NOT matched
  AND S.metadata$action = \'INSERT\' THEN
  INSERT (PASSENGERCODE, FIRSTNAME, LASTNAME, GENDER, AGE, NATIONALITY, TICKETTYPE, PASSENGERSTATUS)
  VALUES (S.PASSENGERCODE, S.FIRSTNAME, S.LASTNAME, S.GENDER, 
  S.AGE, S.NATIONALITY, S.TICKETTYPE, S.PASSENGERSTATUS);

  MERGE INTO AIRPORTS as T
  USING (SELECT *
  FROM raw_table_stream) AS S
  ON T.AIRPORTNAME = S.AIRPORTNAME
  WHEN matched AND S.metadata$action = \'INSERT\' AND S.metadata$isupdate
  THEN
  UPDATE SET T.AIRPORTNAME = S.AIRPORTNAME, T.ARRIVALAIRPORT = S.ARRIVALAIRPORT
  WHEN matched
  AND S.metadata$action = \'DELETE\' THEN DELETE
  WHEN NOT matched
  AND S.metadata$action = \'INSERT\' THEN
  INSERT (AIRPORTNAME, ARRIVALAIRPORT)
  VALUES (S.AIRPORTNAME, S.ARRIVALAIRPORT);

  MERGE INTO COUNTRIES as T
  USING (SELECT *
  FROM raw_table_stream) AS S
  ON T.AIRPORTCOUNTRYCODE = S.AIRPORTCOUNTRYCODE
  WHEN matched AND S.metadata$action = \'INSERT\' AND S.metadata$isupdate
  THEN
  UPDATE SET T.AIRPORTCOUNTRYCODE = S.AIRPORTCOUNTRYCODE, T.COUNTRYNAME = S.COUNTRYNAME
  WHEN matched
  AND S.metadata$action = \'DELETE\' THEN DELETE
  WHEN NOT matched
  AND S.metadata$action = \'INSERT\' THEN
  INSERT (AIRPORTCOUNTRYCODE, COUNTRYNAME)
  VALUES (S.AIRPORTCOUNTRYCODE, S.COUNTRYNAME);
  
  MERGE INTO CONTINENTS as T
  USING (SELECT *
  FROM raw_table_stream) AS S
  ON T.AIRPORTCONTINENT = S.AIRPORTCONTINENT
  WHEN matched AND S.metadata$action = \'INSERT\' AND S.metadata$isupdate
  THEN
  UPDATE SET T.AIRPORTCONTINENT = S.AIRPORTCONTINENT, T.CONTINENTS = S.CONTINENTS
  WHEN matched
  AND S.metadata$action = \'DELETE\' THEN DELETE
  WHEN NOT matched
  AND S.metadata$action = \'INSERT\' THEN
  INSERT (AIRPORTCONTINENT, CONTINENTS)
  VALUES (S.AIRPORTCONTINENT, S.CONTINENTS);

  MERGE INTO PLANES as T
  USING (SELECT * FROM raw_table_stream
  JOIN AIRPORTS ON AIRPORTS.AIRPORTNAME = raw_table_stream.AIRPORTNAME
  JOIN PASSENGERS ON PASSENGERS.PASSENGERCODE = raw_table_stream.PASSENGERCODE
  JOIN COUNTRIES ON COUNTRIES.AIRPORTCOUNTRYCODE = raw_table_stream.AIRPORTCOUNTRYCODE
  JOIN CONTINENTS ON CONTINENTS.AIRPORTCONTINENT = raw_table_stream.AIRPORTCONTINENT) AS S
  ON T.DEPARTUREDATE = S.DEPARTUREDATE AND T.PILOTNAME = S.PILOTNAME AND T.FLIGHTSTATUS = S.FLIGHTSTATUS
  WHEN matched AND S.metadata$action = \'INSERT\' AND S.metadata$isupdate
  THEN
  UPDATE SET T.DEPARTUREDATE = S.DEPARTUREDATE, T.PILOTNAME = S.PILOTNAME, T.FLIGHTSTATUS = S.FLIGHTSTATUS
  WHEN matched
  AND S.metadata$action = \'DELETE\' THEN DELETE
  WHEN NOT matched
  AND S.metadata$action = \'INSERT\' THEN
  INSERT ( DEPARTUREDATE, PILOTNAME, FLIGHTSTATUS, PASSENGERID, AIRPORTID, COUNTRYID, CONTINENTID)
  VALUES ( S.DEPARTUREDATE, S.PILOTNAME, S.FLIGHTSTATUS, S.PASSENGERID, S.AIRPORTID, S.COUNTRYID, S.CONTINENTID);
  
  COMMIT;
  
  RETURN ''Finished creating stored procedures INITIAL_LOAD_TO_PLANES'';
END';

CREATE OR REPLACE PROCEDURE CREATE_SECURE_VIEW()
RETURNS VARCHAR(16777216)
LANGUAGE SQL
EXECUTE AS CALLER
AS 'BEGIN
  BEGIN TRANSACTION;

    CREATE OR REPLACE secure VIEW SV_PLANES AS
    SELECT SV.* from PLANES SV 
    JOIN AIRPORTS AIR ON AIR.AIRPORTID = SV.AIRPORTID
    JOIN ROLES_MAPPING RM
    ON AIR.ARRIVALAIRPORT = RM.ARRIVALAIRPORT
    AND current_role() = RM.role_name;

  COMMIT;

  RETURN ''Finished creating stored procedures INITIAL_LOAD_TO_PLANES'';
END';

CREATE OR REPLACE PROCEDURE LOAD_DATA_MARTS()
RETURNS VARCHAR(16777216)
LANGUAGE SQL
EXECUTE AS CALLER
AS 'BEGIN
  BEGIN TRANSACTION;

  INSERT INTO PASSENGERS_PREFERENCES (DEPARTUREDATE, FLIGHTSTATUS, PASSENGERCODE, AGE, GENDER, NATIONALITY, TICKETTYPE, ARRIVALAIRPORT, AIRPORTNAME)
  SELECT DEPARTUREDATE, FLIGHTSTATUS, PASSENGERS.PASSENGERCODE, PASSENGERS.AGE,PASSENGERS.GENDER,PASSENGERS.NATIONALITY, PASSENGERS.TICKETTYPE, AIRPORTS.ARRIVALAIRPORT, AIRPORTS.AIRPORTNAME FROM PLANES
  JOIN AIRPORTS ON AIRPORTS.AIRPORTID = PLANES.AIRPORTID
  JOIN PASSENGERS ON PASSENGERS.PASSENGERID = PLANES.PASSENGERID;

  INSERT INTO AIROPORTS_INFORMATION (ARRIVALAIRPORT, AIRPORTNAME, AIRPORTCOUNTRYCODE, COUNTRYNAME, AIRPORTCONTINENT, CONTINENTS)
  SELECT AIRPORTS.ARRIVALAIRPORT,AIRPORTS.AIRPORTNAME, COUNTRIES.AIRPORTCOUNTRYCODE, COUNTRIES.COUNTRYNAME,CONTINENTS.AIRPORTCONTINENT, CONTINENTS.CONTINENTS FROM PLANES
  JOIN AIRPORTS ON AIRPORTS.AIRPORTID = PLANES.AIRPORTID
  JOIN COUNTRIES ON COUNTRIES.COUNTRYID = PLANES.COUNTRYID
  JOIN CONTINENTS ON CONTINENTS.CONTINENTID = PLANES.CONTINENTID;

  COMMIT;

  RETURN ''Finished creating stored procedures INITIAL_LOAD_TO_PLANES'';
END';