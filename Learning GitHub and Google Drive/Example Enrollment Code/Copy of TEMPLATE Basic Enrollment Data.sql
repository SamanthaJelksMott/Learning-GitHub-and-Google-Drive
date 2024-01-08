/*	in coll18_production */

/*	Revision history:
		JDT 9/27/2023: Added grade scheme to the join condition for the GRADES table, replace code, person gender, and ethnicity-race category.
		JDT 5/14/2023: Modified view into a snippet for general use as a starting point for future queries related to enrollment data.
		SMJ 3/1/2023: Created view in response to a specific request for enrollment data related to specific departments/subjects.
*/

SELECT
	C.STC_TERM 
	, T.TERM_DESC
	, CONVERT(VARCHAR(4),T.TERM_REPORTING_YEAR)+'*'+CONVERT(VARCHAR(1),T.TERM_SEQUENCE_NO) TERM_SEQ
	, T.TERM_START_DATE
	, CASE
			WHEN T.TERM_DESC LIKE 'Fall%' OR T.TERM_DESC LIKE 'Winter%' THEN COALESCE(TL.TERM_CENSUS_DATES, DATEADD(D,-1,T.TERM_DROP_GRADE_REQD_DATE),DATEADD(D,14,T.TERM_START_DATE))
			ELSE DATEADD(D,14,T.TERM_START_DATE)
		END TERM_CENSUS_DATE
	, T.TERM_END_DATE
	, C.STC_PERSON_ID
	, (0+CONVERT(CHAR(8),T.TERM_START_DATE,112)-CONVERT(CHAR(8),P.BIRTH_DATE,112))/10000 TERM_AGE
	, P.BIRTH_DATE
	, ETH.IPEDS_ETH_RACE_DESC
	, P.GENDER
	, C.STUDENT_ACAD_CRED_ID
	, C.STC_ACAD_LEVEL
	, S.STC_STATUS
	, STV.VAL_EXTERNAL_REPRESENTATION STC_STATUS_DESC
	, S.STC_STATUS_DATE
	, C.STC_CRED_TYPE
	, CT.CRTP_DESC
	, C.STC_SUBJECT
	, RIGHT(C.STC_COURSE_NAME,LEN(C.STC_COURSE_NAME)-CHARINDEX('-',C.STC_COURSE_NAME)) CRSE_NUM
	, C.STC_COURSE SYS_CRSE
	, CS.SEC_NO
	, CS.COURSE_SECTIONS_ID
	, C.STC_COURSE_NAME
	, CS.SEC_NAME
	, C.STC_TITLE
	, REPLACE(CRS.CRS_TITLE,'�',' ') CRS_TITLE
	, C.STC_START_DATE
	, C.STC_END_DATE
	, G.GRD_GRADE
	, G.GRD_VALUE
	, C.STC_REPL_CODE
	, C.STC_COURSE_LEVEL
	, DD.DEPT1
	, DD.DEPT2
	, DD.DEPT3
	, DD.DIV1
	, DD.DIV2
	, DD.DIV3
	, COALESCE(C.STC_CRED, CS.SEC_MIN_CRED) STC_CRED			-- in the very unlikely event that the student has no STC_CRED, pull the minimum value from the section record instead
	, C.STC_ATT_CRED
	, C.STC_CMPL_CRED
	, C.STC_GPA_CRED
	, CON.CT_HRS
	, C.STC_GRADE_SCHEME
	, C.STC_VERIFIED_GRADE_DATE
	, CS.SEC_FACULTY_INFO

FROM
	STUDENT_ACAD_CRED C
	JOIN STC_STATUSES S
		ON C.STUDENT_ACAD_CRED_ID=S.STUDENT_ACAD_CRED_ID
		AND S.POS=1
	LEFT OUTER JOIN CRED_TYPES CT
		ON CT.CRED_TYPES_ID=C.STC_CRED_TYPE
	LEFT OUTER JOIN VALS STV
		ON STV.VAL_MINIMUM_INPUT_STRING=S.STC_STATUS
		AND STV.VALCODE_ID='STUDENT.ACAD.CRED.STATUSES'
	JOIN TERMS T
		ON C.STC_TERM=T.TERMS_ID
	LEFT OUTER JOIN TERMS_LS TL
		ON T.TERMS_ID=TL.TERMS_ID
		AND TL.POS=1
	LEFT OUTER JOIN GRADES G
		ON C.STC_VERIFIED_GRADE=G.GRADES_ID
		AND C.STC_GRADE_SCHEME=G.GRD_GRADE_SCHEME
	JOIN STUDENT_COURSE_SEC SC
		ON C.STC_STUDENT_COURSE_SEC=SC.STUDENT_COURSE_SEC_ID
	LEFT OUTER JOIN COURSE_SECTIONS CS
		ON SC.SCS_COURSE_SECTION=CS.COURSE_SECTIONS_ID
	LEFT OUTER JOIN
		(
			SELECT X.COURSE_SECTIONS_ID
				, D1.DEPTS_DESC+' ('+D1.DEPTS_ID+')' DEPT1
				, CASE WHEN D2.DEPTS_ID<>D1.DEPTS_ID THEN D2.DEPTS_DESC+' ('+D2.DEPTS_ID+')' END DEPT2
				, CASE WHEN D3.DEPTS_ID<>D1.DEPTS_ID AND D3.DEPTS_ID<>D2.DEPTS_ID THEN D3.DEPTS_DESC+' ('+D3.DEPTS_ID+')' END DEPT3
				, V1.DIV_DESC+' ('+V1.DIVISIONS_ID+')' DIV1
				, CASE WHEN V2.DIVISIONS_ID<>V1.DIVISIONS_ID THEN V2.DIV_DESC+' ('+V2.DIVISIONS_ID+')' END DIV2
				, CASE WHEN V3.DIVISIONS_ID<>V1.DIVISIONS_ID AND V3.DIVISIONS_ID<>V2.DIVISIONS_ID THEN V3.DIV_DESC+' ('+V3.DIVISIONS_ID+')' END DIV3
			FROM
				(
					SELECT COURSE_SECTIONS_ID
						, MAX(CASE WHEN POS = 1 THEN SEC_DEPTS END) DEPT1
						, MAX(CASE WHEN POS = 2 THEN SEC_DEPTS END) DEPT2
						, MAX(CASE WHEN POS = 3 THEN SEC_DEPTS END) DEPT3
					FROM SEC_DEPARTMENTS
					WHERE SEC_DEPTS IS NOT NULL
					GROUP BY COURSE_SECTIONS_ID
				) X
				LEFT OUTER JOIN DEPTS D1 ON X.DEPT1=D1.DEPTS_ID
				LEFT OUTER JOIN DIVISIONS V1 ON D1.DEPTS_DIVISION=V1.DIVISIONS_ID
				LEFT OUTER JOIN DEPTS D2 ON X.DEPT2=D2.DEPTS_ID
				LEFT OUTER JOIN DIVISIONS V2 ON D2.DEPTS_DIVISION=V2.DIVISIONS_ID
				LEFT OUTER JOIN DEPTS D3 ON X.DEPT3=D3.DEPTS_ID
				LEFT OUTER JOIN DIVISIONS V3 ON D3.DEPTS_DIVISION=V3.DIVISIONS_ID
		) DD
		ON CS.COURSE_SECTIONS_ID=DD.COURSE_SECTIONS_ID
	JOIN COURSES CRS
		ON CS.SEC_COURSE=CRS.COURSES_ID
	LEFT OUTER JOIN
		(
			SELECT COURSE_SECTIONS_ID, SUM(CON.SEC_CONTACT_HOURS) CT_HRS
			FROM SEC_CONTACT CON
			WHERE SEC_INSTR_METHODS IS NOT NULL
			GROUP BY COURSE_SECTIONS_ID
		) CON ON CS.COURSE_SECTIONS_ID=CON.COURSE_SECTIONS_ID
	LEFT OUTER JOIN PERSON P
		ON C.STC_PERSON_ID=P.ID
	LEFT OUTER JOIN
		(
			SELECT X.ID
				, CASE
						WHEN FP1.VAL_ACTION_CODE_1 = 'NRA'
							OR ISNULL(VE1.VAL_ACTION_CODE_1,'X') = 'NRA'
							OR ISNULL(VE2.VAL_ACTION_CODE_1,'X') = 'NRA'
							OR ISNULL(VR1.VAL_ACTION_CODE_1,'X') = 'NRA'
							OR ISNULL(VR2.VAL_ACTION_CODE_1,'X') = 'NRA'
							OR ISNULL(VR3.VAL_ACTION_CODE_1,'X') = 'NRA'
							OR ISNULL(VR4.VAL_ACTION_CODE_1,'X') = 'NRA'
							OR ISNULL(VR5.VAL_ACTION_CODE_1,'X') = 'NRA' THEN 'U.S. Nonresident'
						WHEN VE1.VAL_ACTION_CODE_1 = 'H' THEN 'Hispanic'
						WHEN (X.RACE2 IS NOT NULL AND VR1.VAL_ACTION_CODE_1 <> VR2.VAL_ACTION_CODE_1)
							OR (X.RACE3 IS NOT NULL AND VR1.VAL_ACTION_CODE_1 <> VR3.VAL_ACTION_CODE_1)
							OR (X.RACE4 IS NOT NULL AND VR1.VAL_ACTION_CODE_1 <> VR4.VAL_ACTION_CODE_1)
							OR (X.RACE5 IS NOT NULL AND VR1.VAL_ACTION_CODE_1 <> VR5.VAL_ACTION_CODE_1) THEN 'Two or More Races'
						WHEN VR1.VAL_ACTION_CODE_1 = '1' THEN 'American Indian/Alaska Native'
						WHEN VR1.VAL_ACTION_CODE_1 = '2' THEN 'Asian'
						WHEN VR1.VAL_ACTION_CODE_1 = '3' THEN 'Black or African American'
						WHEN VR1.VAL_ACTION_CODE_1 = '4' THEN 'Hawaiian/Pacific Islander'
						WHEN VR1.VAL_ACTION_CODE_1 = '5' THEN 'White'
						ELSE 'Unknown'
					END IPEDS_ETH_RACE_DESC
				, FP.FPER_ALIEN_STATUS ALIEN_STATUS, FP1.VAL_EXTERNAL_REPRESENTATION ALIEN_DESC, FP1.VAL_ACTION_CODE_1 ALIEN_ACTION
				, X.ETH1, VE1.VAL_EXTERNAL_REPRESENTATION ETH1_DESC, VE1.VAL_ACTION_CODE_1 ETH1_ACTION
				, X.ETH2, VE2.VAL_EXTERNAL_REPRESENTATION ETH2_DESC, VE2.VAL_ACTION_CODE_1 ETH2_ACTION
				, X.RACE1, VR1.VAL_EXTERNAL_REPRESENTATION RACE1_DESC, VR1.VAL_ACTION_CODE_1 RACE1_ACTION
				, X.RACE2, VR2.VAL_EXTERNAL_REPRESENTATION RACE2_DESC, VR2.VAL_ACTION_CODE_1 RACE2_ACTION
				, X.RACE3, VR3.VAL_EXTERNAL_REPRESENTATION RACE3_DESC, VR3.VAL_ACTION_CODE_1 RACE3_ACTION
				, X.RACE4, VR4.VAL_EXTERNAL_REPRESENTATION RACE4_DESC, VR4.VAL_ACTION_CODE_1 RACE4_ACTION
				, X.RACE5, VR5.VAL_EXTERNAL_REPRESENTATION RACE5_DESC, VR5.VAL_ACTION_CODE_1 RACE5_ACTION

			FROM
				(
					SELECT P.ID
						, MAX(CASE WHEN PL.POS = 1 THEN PL.PER_ETHNICS END) ETH1
						, MAX(CASE WHEN PL.POS = 2 THEN PL.PER_ETHNICS END) ETH2
						, MAX(CASE WHEN PL.POS = 1 THEN PL.PER_RACES END) RACE1
						, MAX(CASE WHEN PL.POS = 2 THEN PL.PER_RACES END) RACE2
						, MAX(CASE WHEN PL.POS = 3 THEN PL.PER_RACES END) RACE3
						, MAX(CASE WHEN PL.POS = 4 THEN PL.PER_RACES END) RACE4
						, MAX(CASE WHEN PL.POS = 5 THEN PL.PER_RACES END) RACE5
					FROM PERSON P LEFT OUTER JOIN PERSON_LS PL ON P.ID=PL.ID
					WHERE COALESCE(P.PERSON_CORP_INDICATOR,'N') = 'N'
					GROUP BY P.ID
				) X

				LEFT OUTER JOIN FOREIGN_PERSON FP ON X.ID=FP.FOREIGN_PERSON_ID
				LEFT OUTER JOIN VALS FP1 ON FP1.VALCODE_ID='ALIEN.STATUSES' AND FP.FPER_ALIEN_STATUS=FP1.VAL_INTERNAL_CODE
				LEFT OUTER JOIN VALS VE1 ON VE1.VALCODE_ID='PERSON.ETHNICS' AND X.ETH1=VE1.VAL_INTERNAL_CODE
				LEFT OUTER JOIN VALS VE2 ON VE2.VALCODE_ID='PERSON.ETHNICS' AND X.ETH2=VE2.VAL_INTERNAL_CODE
				LEFT OUTER JOIN VALS VR1 ON VR1.VALCODE_ID='PERSON.RACES' AND X.RACE1=VR1.VAL_INTERNAL_CODE
				LEFT OUTER JOIN VALS VR2 ON VR2.VALCODE_ID='PERSON.RACES' AND X.RACE2=VR2.VAL_INTERNAL_CODE
				LEFT OUTER JOIN VALS VR3 ON VR3.VALCODE_ID='PERSON.RACES' AND X.RACE3=VR3.VAL_INTERNAL_CODE
				LEFT OUTER JOIN VALS VR4 ON VR4.VALCODE_ID='PERSON.RACES' AND X.RACE4=VR4.VAL_INTERNAL_CODE
				LEFT OUTER JOIN VALS VR5 ON VR5.VALCODE_ID='PERSON.RACES' AND X.RACE5=VR5.VAL_INTERNAL_CODE
		) ETH ON C.STC_PERSON_ID=ETH.ID

WHERE
	C.STC_PERSON_ID IS NOT NULL
	AND C.STC_TERM IS NOT NULL
	AND C.STC_CRED_TYPE IN ('I', 'D')
	AND (S.STC_STATUS IN ('N', 'A', 'W')																		-- still actively enrolled in section or withdrew after census day
		OR (C.STC_VERIFIED_GRADE IS NOT NULL AND S.STC_STATUS='D'))						-- dropped after census day and received a final grade
	AND COALESCE(SC.SCS_PASS_AUDIT,'N') <> 'A'															-- include/exclude auditors
	-- AND CS.SEC_START_DATE BETWEEN '7/1/2022' AND '6/30/2023'							-- option #1: section start date establishes whether to include student
	-- AND C.STC_TERM IN ('F22/23', 'W22/23', 'S22/23')											-- option #2: section term establishes whether to include student
	-- AND C.STC_ACAD_LEVEL <> 'C' AND C.STC_CRED_TYPE IN ('I', 'D')				-- QC check
	-- AND C.STC_TERM LIKE 'N%' AND C.STC_CRED_TYPE IN ('I', 'D')						-- QC check
	-- AND C.STC_TERM NOT IN ('S21/22', 'F22/23', 'W22/23, 'S22/23')				-- QC check

ORDER BY CONVERT(VARCHAR(4),T.TERM_REPORTING_YEAR)+'*'+CONVERT(VARCHAR(1),T.TERM_SEQUENCE_NO), CS.SEC_NAME, C.STC_PERSON_ID