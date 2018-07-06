USE WSO2IS_DB;      -- Replace DATABASE_NAME with your database name
DELIMITER $$

DROP PROCEDURE IF EXISTS WSO2_TOKEN_CLEANUP_SP$$
CREATE PROCEDURE WSO2_TOKEN_CLEANUP_SP ()

BEGIN

-- ------------------------------------------
-- DECLARE VARIABLES
-- ------------------------------------------
DECLARE batchSize INT;
DECLARE backupTables BOOLEAN;
DECLARE sleepTime FLOAT;
DECLARE safePeriod INT;
DECLARE deleteTimeLimit DATETIME;
DECLARE rowCount INT;
DECLARE enableLog BOOLEAN;
DECLARE logLevel VARCHAR(10);
DECLARE enableAudit BOOLEAN;

-- ------------------------------------------
-- CONFIGURABLE ATTRIBUTES
-- ------------------------------------------
SET batchSize = 10000;      -- SET BATCH SIZE FOR AVOID TABLE LOCKS    [DEFAULT : 10000]
SET backupTables = TRUE;    -- SET IF TOKEN TABLE NEEDS TO BACKUP BEFORE DELETE     [DEFAULT : TRUE]
SET sleepTime = 2;          -- SET SLEEP TIME FOR AVOID TABLE LOCKS     [DEFAULT : 2]
SET safePeriod = 2;         -- SET SAFE PERIOD OF HOURS FOR TOKEN DELETE, SINCE TOKENS COULD BE CASHED    [DEFAULT : 2]
SET deleteTimeLimit = DATE_ADD(NOW(), INTERVAL -(safePeriod) HOUR);    -- SET CURRENT TIME - safePeriod FOR BEGIN THE TOKEN DELETE
SET @rowCount = 0;
SET enableLog = TRUE;       -- ENABLE LOGGING [DEFAULT : FALSE]
SET @logLevel = 'DEBUG';    -- SET LOG LEVELS : TRACE , DEBUG
SET enableAudit = FALSE;    -- SET TRUE FOR  KEEP TRACK OF ALL THE DELETED TOKENS USING A TABLE    [DEFAULT : FALSE]

SET SQL_MODE = 'ALLOW_INVALID_DATES';                             -- MAKE THIS UNCOMMENT IF MYSQL THROWS "ERROR 1067 (42000): Invalid default value for 'TIME_CREATED'"
-- SET SESSION TRANSACTION ISOLATION LEVEL READ UNCOMMITTED ;      -- SET ISOLATION LEVEL TO AVOID TABLE LOCKS IN SELECT.


SELECT 'TOKEN_CLEANUP_SP STARTED .... !' AS 'INFO LOG';

IF (backupTables)
THEN
    SELECT 'TABLE BACKUP STARTED ... !' AS 'INFO LOG';
-- ------------------------------------------------------
-- BACKUP IDN_OAUTH2_ACCESS_TOKEN TABLE
-- ------------------------------------------------------
    IF (EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'IDN_OAUTH2_ACCESS_TOKEN_BAK'))
    THEN
        DROP TABLE IDN_OAUTH2_ACCESS_TOKEN_BAK;
    END IF;

    IF (enableLog AND @logLevel IN ('DEBUG','TRACE'))
    THEN
        SELECT 'BACKING UP IDN_OAUTH2_ACCESS_TOKEN TOKENS :' AS 'DEBUG LOG', COUNT(1) FROM IDN_OAUTH2_ACCESS_TOKEN;
    END IF;

    IF (enableLog  AND @logLevel IN ('TRACE') )
    THEN
        SELECT 'BACKING UP IDN_OAUTH2_ACCESS_TOKEN TOKENS INTO IDN_OAUTH2_ACCESS_TOKEN_BAK TABLE ...' AS 'TRACE LOG';
    END IF;

    CREATE TABLE IDN_OAUTH2_ACCESS_TOKEN_BAK SELECT * FROM IDN_OAUTH2_ACCESS_TOKEN;

    IF (enableLog  AND @logLevel IN ('TRACE') )
    THEN
        SELECT 'BACKING UP IDN_OAUTH2_ACCESS_TOKEN_BAK COMPLETED !' AS 'TRACE LOG';
    END IF;

-- ------------------------------------------------------
-- BACKUP IDN_OAUTH2_AUTHORIZATION_CODE TABLE
-- ------------------------------------------------------
    IF (EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'IDN_OAUTH2_AUTHORIZATION_CODE_BAK'))
    THEN
        DROP TABLE IDN_OAUTH2_AUTHORIZATION_CODE_BAK;
    END IF;

    IF (enableLog  AND @logLevel IN ('DEBUG','TRACE') )
    THEN
        SELECT 'BACKING UP IDN_OAUTH2_AUTHORIZATION_CODE TOKENS :' AS 'DEBUG LOG', COUNT(1) FROM IDN_OAUTH2_AUTHORIZATION_CODE;
    END IF;

    IF (enableLog  AND @logLevel IN ('TRACE') )
    THEN
        SELECT 'BACKING UP IDN_OAUTH2_AUTHORIZATION_CODE TOKENS INTO IDN_OAUTH2_AUTHORIZATION_CODE_BAK TABLE ...' AS 'TRACE LOG';
    END IF;

    CREATE TABLE IDN_OAUTH2_AUTHORIZATION_CODE_BAK SELECT * FROM IDN_OAUTH2_AUTHORIZATION_CODE;

    IF (enableLog  AND @logLevel IN ('TRACE') )
    THEN
        SELECT 'BACKING UP IDN_OAUTH2_AUTHORIZATION_CODE_BAK COMPLETED !' AS 'TRACE LOG';
    END IF;

    SELECT 'TABLE BACKUP COMPLETED !' AS 'INFO LOG';

END IF;


-- ------------------------------------------------------
-- CREATING IDN_OAUTH2_ACCESS_TOKEN_CLEANUP_AUDITLOG FOR DELETING TOKENS
-- ------------------------------------------------------
IF (enableAudit)
THEN
    IF (NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'IDN_OAUTH2_ACCESS_TOKEN_CLEANUP_AUDITLOG'))
    THEN
          CREATE TABLE IDN_OAUTH2_ACCESS_TOKEN_CLEANUP_AUDITLOG SELECT * FROM IDN_OAUTH2_ACCESS_TOKEN WHERE 1 = 2;
    END IF;

    IF (NOT EXISTS (SELECT * FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_NAME = 'IDN_OAUTH2_AUTHORIZATION_CODE_CLEANUP_AUDITLOG'))
    THEN
          CREATE TABLE IDN_OAUTH2_AUTHORIZATION_CODE_CLEANUP_AUDITLOG SELECT * FROM IDN_OAUTH2_AUTHORIZATION_CODE WHERE 1 = 2;
    END IF;

END IF;


-- ------------------------------------------------------
-- BATCH DELETE IDN_OAUTH2_ACCESS_TOKEN
-- ------------------------------------------------------
SELECT 'BATCH DELETE ON IDN_OAUTH2_ACCESS_TOKEN STARTED .... !' AS 'INFO LOG';

IF (enableLog AND @logLevel IN ('DEBUG','TRACE'))
THEN
    SELECT 'TOTAL TOKENS ON IDN_OAUTH2_ACCESS_TOKEN TABLE BEFORE DELETE' AS 'DEBUG LOG', COUNT(1) FROM IDN_OAUTH2_ACCESS_TOKEN;
END IF;

IF (enableLog AND @logLevel IN ('DEBUG','TRACE'))
THEN
    SELECT 'TOTAL TOKENS SHOULD BE DELETED FROM IDN_OAUTH2_ACCESS_TOKEN' AS 'DEBUG LOG', COUNT(1) FROM IDN_OAUTH2_ACCESS_TOKEN WHERE TOKEN_STATE IN ('EXPIRED','INACTIVE','REVOKED') OR (TOKEN_STATE = 'ACTIVE' AND (deleteTimeLimit > DATE_ADD(TIME_CREATED, INTERVAL +((VALIDITY_PERIOD/1000)/60) MINUTE)) AND (deleteTimeLimit > DATE_ADD(REFRESH_TOKEN_TIME_CREATED, INTERVAL +((REFRESH_TOKEN_VALIDITY_PERIOD/1000)/60) MINUTE)));
END IF;

IF (enableLog AND @logLevel IN ('DEBUG','TRACE'))
THEN
    SELECT 'TOTAL TOKENS SHOULD BE RETAIN IN IDN_OAUTH2_ACCESS_TOKEN' AS 'DEBUG LOG', COUNT(1) FROM IDN_OAUTH2_ACCESS_TOKEN WHERE TOKEN_STATE = 'ACTIVE' AND (deleteTimeLimit < DATE_ADD(TIME_CREATED, INTERVAL +((VALIDITY_PERIOD/1000)/60) MINUTE)) OR (deleteTimeLimit < DATE_ADD(REFRESH_TOKEN_TIME_CREATED, INTERVAL +((REFRESH_TOKEN_VALIDITY_PERIOD/1000)/60) MINUTE));
END IF;


IF (enableAudit)
THEN
  INSERT INTO IDN_OAUTH2_ACCESS_TOKEN_CLEANUP_AUDITLOG SELECT * FROM IDN_OAUTH2_ACCESS_TOKEN WHERE TOKEN_STATE IN ('EXPIRED','INACTIVE','REVOKED') OR (TOKEN_STATE = 'ACTIVE' AND (deleteTimeLimit > DATE_ADD(TIME_CREATED, INTERVAL +((VALIDITY_PERIOD/1000)/60) MINUTE)) AND (deleteTimeLimit > DATE_ADD(REFRESH_TOKEN_TIME_CREATED, INTERVAL +((REFRESH_TOKEN_VALIDITY_PERIOD/1000)/60) MINUTE))) LIMIT batchSize;
END IF;


REPEAT
IF ((@rowCount > 0))
THEN
    DO SLEEP(sleepTime);
END IF;
DELETE FROM IDN_OAUTH2_ACCESS_TOKEN WHERE TOKEN_STATE IN ('EXPIRED','INACTIVE','REVOKED') OR (TOKEN_STATE = 'ACTIVE' AND (deleteTimeLimit > DATE_ADD(TIME_CREATED, INTERVAL +((VALIDITY_PERIOD/1000)/60) MINUTE)) AND (deleteTimeLimit > DATE_ADD(REFRESH_TOKEN_TIME_CREATED, INTERVAL +((REFRESH_TOKEN_VALIDITY_PERIOD/1000)/60) MINUTE))) LIMIT batchSize;
SELECT row_count() INTO @rowCount;
IF (enableLog AND @logLevel IN ('TRACE'))
THEN
    SELECT 'BATCH DELETE ON IDN_OAUTH2_ACCESS_TOKEN :' AS 'TRACE LOG', @rowCount;
END IF;
UNTIL @rowCount = 0 END REPEAT;

SELECT 'BATCH DELETE ON IDN_OAUTH2_ACCESS_TOKEN COMPLETED .... !' AS 'INFO LOG';

-- ------------------------------------------------------

-- ------------------------------------------------------
-- BATCH DELETE IDN_OAUTH2_AUTHORIZATION_CODE
-- ------------------------------------------------------
SELECT 'BATCH DELETE ON IDN_OAUTH2_AUTHORIZATION_CODE STARTED .... !' AS 'INFO LOG';

IF (enableLog AND @logLevel IN ('DEBUG','TRACE'))
THEN
    SELECT 'TOTAL TOKENS ON IDN_OAUTH2_AUTHORIZATION_CODE TABLE BEFORE DELETE' AS 'DEBUG LOG', COUNT(1) FROM IDN_OAUTH2_AUTHORIZATION_CODE;
END IF;

IF (enableLog AND @logLevel IN ('DEBUG','TRACE'))
THEN
    SELECT 'TOTAL TOKENS ON SHOULD BE DELETED FROM IDN_OAUTH2_AUTHORIZATION_CODE' AS 'DEBUG LOG', COUNT(1) FROM IDN_OAUTH2_AUTHORIZATION_CODE code WHERE NOT EXISTS (SELECT * FROM IDN_OAUTH2_ACCESS_TOKEN token WHERE token.TOKEN_ID = code.TOKEN_ID) OR STATE NOT IN ('ACTIVE') OR deleteTimeLimit > DATE_ADD(TIME_CREATED , INTERVAL +((VALIDITY_PERIOD/1000)/60) MINUTE) OR TOKEN_ID IS NULL;
END IF;

IF (enableLog AND @logLevel IN ('DEBUG','TRACE'))
THEN
    SELECT 'TOTAL TOKENS ON SHOULD BE RETAIN IN IDN_OAUTH2_AUTHORIZATION_CODE' AS 'DEBUG LOG', COUNT(1) FROM IDN_OAUTH2_AUTHORIZATION_CODE code WHERE EXISTS (SELECT * FROM IDN_OAUTH2_ACCESS_TOKEN token WHERE token.TOKEN_ID = code.TOKEN_ID) AND STATE IN ('ACTIVE') AND deleteTimeLimit < DATE_ADD(TIME_CREATED , INTERVAL +((VALIDITY_PERIOD/1000)/60) MINUTE);
END IF;

IF (enableAudit)
THEN
    INSERT INTO IDN_OAUTH2_AUTHORIZATION_CODE_CLEANUP_AUDITLOG  SELECT * FROM IDN_OAUTH2_AUTHORIZATION_CODE where CODE_ID in ( SELECT * FROM ( select CODE_ID FROM IDN_OAUTH2_AUTHORIZATION_CODE code WHERE NOT EXISTS ( SELECT * FROM IDN_OAUTH2_ACCESS_TOKEN token WHERE token.TOKEN_ID = code.TOKEN_ID AND token.TOKEN_STATE = 'ACTIVE') AND code.STATE NOT IN ( 'ACTIVE' ) ) as x) OR  deleteTimeLimit > DATE_ADD( TIME_CREATED , INTERVAL +(( VALIDITY_PERIOD / 1000 )/ 60 ) MINUTE );
END IF;

REPEAT
IF ((@rowCount > 0))
THEN
    DO SLEEP(sleepTime);
END IF;
  DELETE FROM IDN_OAUTH2_AUTHORIZATION_CODE where CODE_ID in ( SELECT * FROM ( select CODE_ID FROM
    IDN_OAUTH2_AUTHORIZATION_CODE code WHERE NOT EXISTS ( SELECT * FROM IDN_OAUTH2_ACCESS_TOKEN token WHERE token.TOKEN_ID = code.TOKEN_ID AND token.TOKEN_STATE = 'ACTIVE') AND code.STATE NOT IN ( 'ACTIVE' ) ) as x) OR  deleteTimeLimit > DATE_ADD( TIME_CREATED , INTERVAL +(( VALIDITY_PERIOD / 1000 )/ 60 ) MINUTE );

  SELECT row_count() INTO @rowCount;
IF (enableLog AND @logLevel IN ('TRACE'))
THEN
    SELECT 'BATCH DELETE ON IDN_OAUTH2_AUTHORIZATION_CODE:' AS 'TRACE LOG', @rowCount;
END IF;
UNTIL @rowCount = 0 END REPEAT;

SELECT 'BATCH DELETE ON IDN_OAUTH2_AUTHORIZATION_CODE COMPLETED .... !' AS 'INFO LOG';


-- ------------------------------------------------------

IF (enableLog AND @logLevel IN ('DEBUG','TRACE'))
THEN
    SELECT 'TOTAL TOKENS ON IDN_OAUTH2_ACCESS_TOKEN TABLE AFTER DELETE' AS 'DEBUG LOG', COUNT(1) FROM IDN_OAUTH2_ACCESS_TOKEN;
END IF;

IF (enableLog AND @logLevel IN ('DEBUG','TRACE'))
THEN
    SELECT 'TOTAL TOKENS ON IDN_OAUTH2_AUTHORIZATION_CODE TABLE AFTER DELETE' AS 'DEBUG LOG', COUNT(1) FROM IDN_OAUTH2_AUTHORIZATION_CODE;
END IF;

SELECT 'TOKEN_CLEANUP_SP COMPLETED .... !' AS 'INFO LOG';

-- ------------------------------------------------------


END$$

DELIMITER ;
