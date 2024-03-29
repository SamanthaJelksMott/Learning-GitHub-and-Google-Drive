USE [WAREHOUSE]
GO
/****** Object:  StoredProcedure [dbo].[USP_Annual_StarrStudentLoad]    Script Date: 10/11/2023 3:37:25 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[USP_Annual_StarrStudentLoad] (
  @YEAR INT = 0
  , @BEGINDATE INT = 0 -- Used to determine the starting date for Degrees (YYYY0701)
  , @ENDDATE INT = 0 -- Used to determine the ending date for Degrees (YYYY0630)
  , @ETL_JOBID INT = 0
  )
AS
BEGIN
  SET NOCOUNT ON

  DECLARE @CURRENT_DATEID INT = dbo.FN_DateToID(GETDATE())
  DECLARE @NOW DATETIME = GETDATE()
  DECLARE @FAYEAR INT = @YEAR - 1
  DECLARE @COHORTTYPEID INT = (
      SELECT ID
      FROM dbo.DIM_StudentCohortTypes
      WHERE CohortDescription = 'STARR Report'
      )

  SET NOCOUNT ON;

  /*
	*****************************************************
	Load Students to DIM_StudentCohort Table
	Note:  This is shared table used by Blumen & Starfish
	*****************************************************	
	*/
  BEGIN
    DELETE
    FROM dbo.DIM_StudentCohort
    WHERE Year = @YEAR
      AND CohortTypeID = @COHORTTYPEID

    INSERT INTO dbo.DIM_StudentCohort (
      PersonID
      , Year
      , AddDate
      , CohortTypeID
      , CohortStartDateID
      ) (
      SELECT DISTINCT a.PersonID AS PersonID
      , @YEAR AS Year
      , GETDATE() AS AddDate
      , @COHORTTYPEID AS CohortTypeID
      , NULL FROM
      --gets students with active registration during the reporting year
      (
      SELECT stac.StudentPersonID AS PersonID
      FROM dbo.FACT_StudentAcademicCredit stac
      JOIN dbo.DIM_Term term ON stac.TermID = term.ID
      JOIN dbo.DIM_Subject subj ON stac.SubjectID = subj.ID
      JOIN dbo.DIM_CourseSection cs ON stac.CourseSectionID = cs.ID
      LEFT OUTER JOIN dbo.DIM_Grade gr ON stac.VerifiedGradeID = gr.ID
      WHERE term.ReportingYear = @YEAR
        --pulls all credit with a Status of A or N regardless of grade and status of D if grade is not null
        --pulls only non-credit with a grade 
        AND (
          stac.CurrentStatus IN ('A', 'N')
          OR (
            stac.CurrentStatus = 'D'
            AND stac.VerifiedGradeID IS NOT NULL
            )
          )
        --excludes courses with the subject listed below.  Specifically, DLES courses	 
        AND subj.Code NOT IN ('DLES', 'GED', 'MBC.', 'PRE', 'SBMT')
        AND cs.Name <> 'AHLT-HIPAA'
        AND (
          (
            subj.Code <> 'NOCR'
            AND (
              gr.Grade NOT IN ('N', 'H', 'X')
              OR gr.ID IS NULL
              )
            )
          OR (
            subj.Code = 'NOCR'
            AND gr.ID <> 17
            AND gr.ID IS NOT NULL
            )
          )
      
      UNION ALL
      
      --gets students who have earned an award/degree in the reporting year
      SELECT acm.PersonID AS PersonID
      FROM dbo.FACT_AcademicCredentialsMott acm
      JOIN dbo.DIM_Degree deg ON acm.DegreeID = deg.ID
      JOIN dbo.FACT_AcademicCredentialsMottMajor_REL maj ON acm.ID = maj.AcademicCredentialsMottID
      WHERE acm.DegreeDateID BETWEEN @BEGINDATE
          AND @ENDDATE
            --excludes degrees where Code is HNR (Honor) or OTH (Other)
        AND deg.Code NOT IN ('HNR', 'OTH')
      ) a
      )
  END

  BEGIN
    --Remove students from Cohort where the activity is tied to an invalid ID or the birthdate is null (NOCR students)
    DELETE
    FROM dbo.DIM_StudentCohort
    WHERE Year = @YEAR
      AND CohortTypeID = @COHORTTYPEID
      AND PersonID IN (
        SELECT ID
        FROM dbo.VIEW_DIM_StudentCurrentDate
        WHERE FirstName LIKE 'Please%'
          OR FirstName LIKE 'Do N%'
          OR FirstName LIKE 'DO N%'
          OR FirstName IS NULL
          OR LastName LIKE 'Please%'
          OR LastName LIKE 'Do N%'
          OR LastName LIKE 'DO N%'
          OR LastName IS NULL
          OR BirthDate IS NULL
          OR PrivacyFlag = 'DU'
        )
  END

  /* 10-13-2018:  
		Removed 6 records where awards were conferred in Datatel that were invalid.  Timing did not
		allow records to be corrected in Datatel in time for submission.
	*/
  BEGIN
    DELETE
    FROM dbo.DIM_StudentCohort
    WHERE Year = 2018
      AND CohortTypeID = 1
      AND PersonID IN (60153, 510340, 391327, 530304, 168512, 186457)
  END

  /*
	************************************************************
	Load Students in Cohort to AGG_StarrStudentDemographic Table
	************************************************************
	*/
  BEGIN
    DELETE
    FROM dbo.AGG_StarrStudentDemographic
    WHERE CohortYear = @YEAR

    INSERT INTO AGG_StarrStudentDemographic (
      CohortYear
      , StudentPersonID
      , LastName
      , FirstName
      , MiddleName
      , Suffix
      , PersonAlternateID
      , BirthDate
      , Gender
      , FirstRegistrationDateID
      , [State]
      , FamilyContribution
      , EthnicCode
      , ReportedRace
      , ETL_JobID
      , DatatelID
      , IPEDS_RaceEthnicDesc
      )
    SELECT DISTINCT @YEAR
      , co.PersonID
      , REPLACE(REPLACE(LastName, ',', ''), '`', '') LastName
      , REPLACE(REPLACE(FirstName, ',', ''), '`', '') FirstName
      , REPLACE(REPLACE(MiddleName, ',', ''), '`', '') MiddleName
      , Suffix
      , PersonUICID
      , BirthDate
      , Gender
      , reg.FirstRegistrationDateID
      , adr.[State]
      , '' FamilyContribution
      , eth.Code
      , prac.ReportedRace
      , @ETL_JOBID
      , st.Code DatatelID
      , prac.IPEDS_RaceEthnicDesc
    FROM dbo.DIM_StudentCohort co
    LEFT JOIN dbo.VIEW_DIM_StudentCurrentDate st ON co.PersonID = st.ID
    LEFT JOIN dbo.VIEW_FACT_StudentFirstRegistration reg ON co.PersonID = reg.StudentPersonID
    LEFT JOIN dbo.VIEW_FACT_PersonAddressCurrentDate adr ON co.PersonID = adr.PersonID
      AND adr.PreferredResidence = 'Y'
    LEFT JOIN dbo.DIM_PersonEthnic_REL peth ON co.PersonID = peth.PersonID
    LEFT JOIN dbo.DIM_Ethnic eth ON peth.EthnicID = eth.ID
    LEFT JOIN dbo.VIEW_DIM_PersonReportedRace prac ON co.PersonID = prac.PersonID
    WHERE co.CohortTypeID = @COHORTTYPEID
      AND co.Year = @YEAR
      AND st.PersonUICID IS NOT NULL
  END

  /*
	************************************************************
	Load Students in Cohort to AGG_StarrStudentAward Table
	************************************************************
	*/
  BEGIN
    DELETE
    FROM dbo.AGG_StarrStudentAward
    WHERE CohortYear = @YEAR

    INSERT INTO AGG_StarrStudentAward (
      CohortYear
      , StudentPersonID
      , AcademicCredentialsMottID
      , DegreeCode
      , DegreeDescription
      , DegreeDateID
      , MajorID
      , MajorCode
      , MajorDescription
      , CIPCode
      , ETL_JobID
      , IsCTEProgram
      )
    SELECT @YEAR
      , co.PersonID
      , awm.AcademicCredentialsMottID
      , deg.Code DegreeCode
      , deg.Description DegreeDescription
      , aw.DegreeDateID
      , maj.ID MajorID
      , maj.Code MajorCode
      , maj.Description MajorDescription
      --These 'default' CIP codes were provided by IR for these programs which were awarded years ago where no valid cip is available
      , COALESCE(cp.Code, CASE maj.Code
          WHEN 'ACHR'
            THEN ('15.0501')
          WHEN 'ACTG'
            THEN ('52.0301')
          WHEN 'ART'
            THEN ('24.0101')
          WHEN 'AUBY'
            THEN ('47.0603')
          WHEN 'AUTO'
            THEN ('47.0604')
          WHEN 'BANK'
            THEN ('52.0801')
          WHEN 'BUSAD'
            THEN ('52.0201')
          WHEN 'BUSN'
            THEN ('52.0101')
          WHEN 'CHLD'
            THEN ('13.1210')
          WHEN 'CISY'
            THEN ('11.0101')
          WHEN 'COMPA'
            THEN ('11.0101')
          WHEN 'COMPO'
            THEN ('11.0202')
          WHEN 'CRJU'
            THEN ('43.0107')
          WHEN 'CUL.'
            THEN ('12.0503')
          WHEN 'CUSTE'
            THEN ('15.0503')
          WHEN 'DAST'
            THEN ('51.0601')
          WHEN 'DHYG'
            THEN ('51.0602')
          WHEN 'DPCRT'
            THEN ('52.0407')
          WHEN 'DRFT'
            THEN ('15.1301')
          WHEN 'ECE'
            THEN ('13.1210')
          WHEN 'ELEC'
            THEN ('15.0303')
          WHEN 'FIRE'
            THEN ('43.0201')
          WHEN 'FLPW'
            THEN ('15.9999')
          WHEN 'FMG.'
            THEN ('12.0507')
          WHEN 'GENST'
            THEN ('24.0102')
          WHEN 'HAIRS'
            THEN ('12.0412')
          WHEN 'HIST'
            THEN ('26.0401')
          WHEN 'INTER'
            THEN ('16.1603')
          WHEN 'IPS'
            THEN ('11.0401')
          WHEN 'ITCM'
            THEN ('48.9999')
          WHEN 'ITEL'
            THEN ('48.9999')
          WHEN 'ITMA'
            THEN ('48.9999')
          WHEN 'LEGAL'
            THEN ('22.0301')
          WHEN 'MATH'
            THEN ('41.9999')
          WHEN 'MDML1'
            THEN ('15.0612')
          WHEN 'MECHE'
            THEN ('15.0805')
          WHEN 'MERAD'
            THEN ('52.1899')
          WHEN 'MGMT'
            THEN ('52.0201')
          WHEN 'MKTG'
            THEN ('52.1401')
          WHEN 'NURS'
            THEN ('51.3801')
          WHEN 'OISE'
            THEN ('52.0402')
          WHEN 'OISI'
            THEN ('52.1299')
          WHEN 'OISL'
            THEN ('22.0301')
          WHEN 'OISM'
            THEN ('51.0716')
          WHEN 'OTA.'
            THEN ('51.0803')
          WHEN 'PARA'
            THEN ('22.0301')
          WHEN 'PIPE'
            THEN ('46.0502')
          WHEN 'ROBOT'
            THEN ('15.0303')
          WHEN 'RTAD'
            THEN ('51.0908')
          WHEN 'SBM'
            THEN ('52.0701')
          WHEN 'SCI'
            THEN ('26.0101')
          WHEN 'SOCW'
            THEN ('51.1504')
          WHEN 'WORD'
            THEN ('11.0602')
          ELSE NULL
          END) CIPCode
      , @ETL_JOBID
      , CASE pi.OccupationalCode
        WHEN 'O'
          THEN (1)
        WHEN 'S'
          THEN (1)
        ELSE (0)
        END IsCTEProgram
    FROM dbo.DIM_StudentCohort co
    JOIN dbo.FACT_AcademicCredentialsMott aw ON co.PersonID = aw.PersonID
    JOIN dbo.DIM_Degree deg ON aw.DegreeID = deg.ID
    JOIN dbo.FACT_AcademicCredentialsMottMajor_REL awm ON aw.ID = awm.AcademicCredentialsMottID
    JOIN dbo.DIM_Major maj ON awm.MajorID = maj.ID
    LEFT JOIN dbo.DIM_AcademicProgram pgm ON maj.Code = pgm.Code
    LEFT JOIN dbo.DIM_CIP cp ON pgm.CIPID = cp.ID
    LEFT JOIN (
      SELECT MCCAcademicProgramAlias
        , max(ProgramInventoryDate) MaxDate
      FROM dbo.DIM_ProgramInventoryFile
      GROUP BY MCCAcademicProgramAlias
      ) pimax ON pimax.MCCAcademicProgramAlias = maj.Code
    LEFT JOIN dbo.DIM_ProgramInventoryFile pi ON pi.MCCAcademicProgramAlias = pimax.MCCAcademicProgramAlias
      AND pi.ProgramInventoryDate = pimax.MaxDate
    WHERE co.CohortTypeID = @COHORTTYPEID
      AND co.Year = @YEAR
      AND deg.Code NOT IN ('HNR', 'OTH')
  END

  /*
	**************************************************************
	Load Students in Cohort to AGG_StarrStudentProgramByTerm Table
	**************************************************************
	*/
  BEGIN
    DELETE
    FROM dbo.AGG_StarrStudentProgramByTerm
    WHERE CohortYear = @YEAR

    INSERT INTO AGG_StarrStudentProgramByTerm (
      CohortYear
      , StudentPersonID
      , AcademicProgram
      , AcademicProgramName
      , AcademicProgramStartTermID
      , AcademicProgramStartTerm
      , AcademicProgramEndTermID
      , AcademicProgramEndTerm
      , CIP
      , AcademicProgramBestFitOrder
      , AcademicProgramType
      , ProgramStartDateID
      , ProgramEndDateID
      , Degree
      , ETL_JobID
      , IsCTEProgram
      , DegreeLevel
      )
    SELECT @YEAR
      , sc.PersonID
      , prgm.AcademicProgram
      , prgm.Title
      , prgm.AcademicProgramStartTermID
      , prgm.AcademicProgramStartTerm
      , prgm.AcademicProgramEndTermID
      , prgm.AcademicProgramEndTerm
      , cip.Code
      , AcademicProgramBestFitOrder
      , 'Major' AS AcademicProgramType
      , prgm.ProgramStartDateID
      , prgm.ProgramEndDateID
      , prgm.Degree
      , @ETL_JOBID
      , CASE pi.OccupationalCode
        WHEN 'O'
          THEN (1)
        WHEN 'S'
          THEN (1)
        ELSE (0)
        END IsCTEProgram
      , pi.DegreeLevel
    FROM dbo.VIEW_FACT_StudentAcademicProgramCurrentStatusDate prgm
    JOIN dbo.DIM_StudentCohort sc ON prgm.StudentID = sc.PersonID
    JOIN dbo.DIM_AcademicProgram ap ON prgm.AcademicProgramID = ap.ID
    LEFT JOIN dbo.DIM_CIP cip ON ap.CIPID = cip.ID
    LEFT JOIN (
      SELECT MCCAcademicProgramAlias
        , max(ProgramInventoryDate) MaxDate
      FROM dbo.DIM_ProgramInventoryFile
      GROUP BY MCCAcademicProgramAlias
      ) pimax ON pimax.MCCAcademicProgramAlias = ap.Code
    LEFT JOIN dbo.DIM_ProgramInventoryFile pi ON pi.MCCAcademicProgramAlias = pimax.MCCAcademicProgramAlias
      AND pi.ProgramInventoryDate = pimax.MaxDate
    WHERE sc.CohortTypeID = @COHORTTYPEID
      AND sc.Year = @YEAR
      AND ap.Code NOT LIKE '%7'
  END

  /*
	**************************************************************
	Load Students in Cohort to AGG_StarrStudentCourseHistory Table
	**************************************************************
	*/
  BEGIN
    DELETE
    FROM dbo.AGG_StarrStudentCourseHistory
    WHERE CohortYear = @YEAR

    INSERT INTO AGG_StarrStudentCourseHistory (
      CohortYear
      , StudentPersonID
      , Term
      , CourseSectionID
      , CourseSubject
      , CourseNumber
      , CourseName
      , AcademicLevel
      , CreditType
      , CIPCode
      , StartDate
      , EndDate
      , CourseTitle
      , Credits
      , AttemptedCredits
      , CompletedCredits
      , ContactHours
      , CurrentStatus
      , VerifiedGradeID
      , IsCTECourse
      , ETL_JobID
      )
    SELECT @YEAR AS CohortYear
      , co.PersonID AS StudentPersonID
      , t.Code AS Term
      , sec.ID AS CourseSectionID
      --special chars must be removed to pass validation
      , REPLACE(subj.Code, '/', '') AS CourseSubject
      , REPLACE(REPLACE(crs.CourseNumber, '/', ''), '&', '') AS CourseNumber
      , crs.Name AS CourseName
      , al.Code AS AcademicLevel
      , ct.Code AS CreditType
      , cip.Code AS CIPCode
      , coalesce(sec.StartDateID, t.StartDateID) AS StartDate
      , coalesce(sec.EndDateID, t.EndDateID) AS EndDate
      , stac.Title AS CourseTitle
      , stac.Credits AS Credits
      , stac.AttemptedCredits AS AttemptedCredits
      , stac.CompletedCredits AS CompletedCredits
      , sum(coalesce(chour.SectionContactHours, chour.SectionClockHours)) ContactHours
      , stac.CurrentStatus AS CurrentStatus
      , stac.VerifiedGradeID AS VerifiedGradeID
      , CASE 
        WHEN crs.LocalGovernmentCodeID IN (12, 13, 14)
          THEN 'Y'
        ELSE 'N'
        END AS IsCTECourse
      , @ETL_JOBID
    FROM dbo.DIM_StudentCohort co
    JOIN dbo.FACT_StudentAcademicCredit stac ON co.PersonID = stac.StudentPersonID
    JOIN dbo.DIM_Term t ON stac.TermID = t.ID
    JOIN dbo.DIM_Subject subj ON stac.SubjectID = subj.ID
    JOIN dbo.DIM_Course crs ON stac.CourseID = crs.ID
    LEFT JOIN dbo.DIM_CIP cip ON crs.CIPID = cip.ID
    JOIN dbo.DIM_AcademicLevel al ON crs.AcademicLevelID = al.ID
    JOIN dbo.DIM_CreditType ct ON stac.CreditTypeID = ct.ID
    LEFT JOIN dbo.DIM_CourseSection sec ON stac.CourseSectionID = sec.ID
      AND stac.TermID = sec.TermID
      AND sec.Name <> 'AHLT-HIPAA'
    LEFT JOIN dbo.DIM_Grade gr ON stac.VerifiedGradeID = gr.ID
    LEFT JOIN dbo.FACT_CourseSectionContactHour chour ON sec.ID = chour.CourseSectionID
    WHERE co.CohortTypeID = @COHORTTYPEID
      AND co.Year = @YEAR
      --pulls all credit and non-credit with a Status of A or N regardless of grade and status of D if grade is not null
      --pulls only non-credit with a grade 
      AND (
        stac.CurrentStatus IN ('A', 'N')
        OR (
          stac.CurrentStatus = 'D'
          AND stac.VerifiedGradeID IS NOT NULL
          )
        )
      AND
      --excludes courses with the subject listed below.  Specifically, DLES courses	 
      subj.Code NOT IN ('DLES', 'GED', 'MBC.', 'PRE', 'SBMT')
      AND crs.Name <> 'AHLT-HIPAA'
      AND (
        (
          subj.Code <> 'NOCR'
          AND (
            gr.Grade NOT IN ('N', 'H', 'X')
            OR gr.ID IS NULL
            )
          )
        OR (
          subj.Code = 'NOCR'
          AND gr.ID <> 17
          AND gr.ID IS NOT NULL
          )
        )
      --excludes future terms
      AND t.ReportingYear <= @YEAR
    GROUP BY co.Year
      , co.PersonID
      , t.Code
      , sec.ID
      , subj.Code
      , crs.CourseNumber
      , crs.Name
      , al.Code
      , ct.Code
      , cip.Code
      , sec.StartDateID
      , t.StartDateID
      , t.EndDateID
      , sec.EndDateID
      , stac.Title
      , stac.Credits
      , stac.AttemptedCredits
      , stac.CompletedCredits
      , stac.CurrentStatus
      , stac.GradeSchemeID
      , stac.VerifiedGradeID
      , CASE 
        WHEN crs.LocalGovernmentCodeID IN (12, 13, 14)
          THEN 'Y'
        ELSE 'N'
        END
  END

  /*
	******************************************************************************
	Updates AGG_StarrStudentCourseHistory
	Sets the grades for labs, clinicals and quiz course to the grade from the
	lecture course.  Faculty do not grade labs, clinicals & quiz courses.  All
	courses must have a grade to pass validation.
	******************************************************************************
	*/
  BEGIN
    UPDATE a
    SET a.VerifiedGradeID = b.VerifiedGradeID
    FROM dbo.AGG_StarrStudentCourseHistory a
    JOIN dbo.AGG_StarrStudentCourseHistory b ON a.CohortYear = b.CohortYear
      AND a.Term = b.Term
      AND a.StudentPersonID = b.StudentPersonID
      AND substring(a.CourseName, 1, 8) = b.CourseName
    WHERE a.VerifiedGradeID IS NULL
      AND b.VerifiedGradeID IS NOT NULL
      AND a.AcademicLevel = 'C'
      AND a.CohortYear = @YEAR
      AND substring(a.CourseNumber, 4, 1) IN ('L', 'Q', 'M', 'C', 'R')
  END

  /*
	**************************************************************
	Load Students in Cohort to AGG_StarrStudentDualEnrollment Table
	**************************************************************
	*/
  BEGIN
    DELETE
    FROM dbo.AGG_StarrStudentDualEnrollment
    WHERE CohortYear = @YEAR

    INSERT INTO dbo.AGG_StarrStudentDualEnrollment (
      CohortYear
      , Term
      , StudentPersonID
      , StudentTypeCode
      , ETL_JobID
      )
    SELECT DISTINCT @YEAR
      , t.Code
      , cert.StudentPersonID
      , st.Code
      , @ETL_JOBID
    FROM dbo.DIM_StudentCohort co
    JOIN dbo.FACT_DualCertificate cert ON co.PersonID = cert.StudentPersonID
    JOIN dbo.DIM_DualStudentType st ON cert.StudentTypeID = st.ID
    JOIN dbo.DIM_Term t ON cert.TermID = t.ID
    WHERE co.CohortTypeID = @COHORTTYPEID
      AND co.Year = @YEAR
  END

  /*
	**************************************************************
	Load Students in Cohort to AGG_StarrStudentApplication Table
	**************************************************************
	*/
  BEGIN
    DELETE
    FROM dbo.AGG_StarrStudentApplication
    WHERE CohortYear = @YEAR

    INSERT INTO dbo.AGG_StarrStudentApplication (
      CohortYear
      , StudentPersonID
      , ApplicationID
      , ApplicationDateID
      , ReportingStartTerm
      , AdmissionCode
      , AdmissionDescription
      , ETL_JobID
      )
    SELECT DISTINCT @YEAR
      , app.ApplicantPersonID
      , app.ApplicationID
      , app.ApplicationDateID
      , t.Code
      , ads.Code
      , ads.Description
      , @ETL_JOBID
    FROM dbo.DIM_StudentCohort co
    JOIN dbo.VIEW_DIM_ApplicationStatusCurrentDate app ON co.PersonID = app.ApplicantPersonID
    JOIN dbo.DIM_AdmissionStatus ads ON app.AdmissionStatusID = ads.ID
    JOIN dbo.DIM_Term t ON app.ApplicationDateID BETWEEN t.ReportingStartDateID
        AND t.ReportingEndDateID
    WHERE co.CohortTypeID = @COHORTTYPEID
      AND co.Year = @YEAR
  END

  /*
	****************************************************************
	Load Students in Cohort to AGG_StarrStudentAcademicSession Table
	****************************************************************
	*/
  BEGIN
    DELETE
    FROM dbo.AGG_StarrStudentAcademicSession
    WHERE CohortYear = @YEAR

    INSERT INTO AGG_StarrStudentAcademicSession (
      CohortYear
      , StudentPersonID
      , TermID
      , Term
      , TermStartDateID
      , TermEndDateID
      , FirstTermFlag
      , ReadmitTermFlag
      , TermCompletedCredits
      , TermGPA
      , CumulativeCompletedCredits
      , CumulativeGPA
      , TermResidencyStatusCode
      , TermAttemptedCredits
      , PellActionCode
      , PellAwardAmount
      , PellTransmitAmount
      , ETL_JobID
      )
    SELECT DISTINCT sch.CohortYear
      , sch.StudentPersonID
      , t.ID AS TermID
      , sch.Term
      , t.StartDateID AS TermStartDateID
      , t.EndDateID AS TermEndDateID
      , CASE sch.Term
        WHEN MIN(sch.Term) OVER (PARTITION BY sch.StudentPersonID)
          THEN ('Y')
        ELSE ('N')
        END AS FirstTermFlag
      , CASE sch.Term
        WHEN MAX(CASE 
              WHEN sch.Term = ssa.ReportingStartTerm
                AND ssa.AdmissionCode = 'REA'
                THEN (sch.Term)
              ELSE (NULL)
              END) OVER (
            PARTITION BY sch.StudentPersonID
            , sch.Term
            )
          THEN ('Y')
        ELSE ('N')
        END AS ReadmitTermFlag
      , sap.TermGraduationCredits
      , sap.TermGPA
      , sap.CumulativeGraduationCredits
      , sap.CumulativeGPA
      , srs.ResidencyStatusID AS TermResidencyStatusCode
      , SUM(sch.Credits) AS TermAttemptedCredits
      , pell.Code PellActionCode
      , pell.AwardAmount PellAwardAmount
      , pell.TransmitAmount PellTransmitAmount
      , @ETL_JOBID
    FROM dbo.DIM_StudentCohort sc
    JOIN dbo.AGG_StarrStudentCourseHistory sch ON sc.PersonID = sch.StudentPersonID
      AND sc.Year = sch.CohortYear
    JOIN dbo.DIM_Term t ON sch.Term = t.Code
    LEFT JOIN dbo.AGG_StarrStudentApplication ssa ON sch.StudentPersonID = ssa.StudentPersonID
      AND sch.CohortYear = ssa.CohortYear
    LEFT JOIN dbo.VIEW_FACT_StudentTermAcademicProgress sap ON sch.StudentPersonID = sap.StudentPersonID
      AND t.ID = sap.TermID
    LEFT JOIN dbo.VIEW_DIM_StudentTermResidencyStatus srs ON sch.StudentPersonID = srs.StudentPersonID
      AND t.ID = srs.TermID
    LEFT JOIN (
      SELECT finaid.StudentID
        , finaid.TermID
        , act.Code
        , finaid.AwardAmount
        , finaid.TransmitAmount
      FROM dbo.FACT_StudentFinAidAwards_REL finaid
      JOIN dbo.DIM_FAAward aw ON finaid.AwardID = aw.ID
      JOIN dbo.DIM_FAAwardAction act ON finaid.ActionID = act.ID
      WHERE aw.Code IN ('0500', 'PELL')
      ) pell ON sch.StudentPersonID = pell.StudentID
      AND t.ID = pell.TermID
    WHERE sch.VerifiedGradeID IS NOT NULL
      AND sch.CohortYear = @YEAR
      AND sc.CohortTypeID = 1
    GROUP BY sch.CohortYear
      , sch.StudentPersonID
      , t.ID
      , sch.Term
      , t.StartDateID
      , t.EndDateID
      , sap.TermGraduationCredits
      , sap.TermGPA
      , sap.CumulativeGraduationCredits
      , sap.CumulativeGPA
      , ssa.ReportingStartTerm
      , ssa.AdmissionCode
      , srs.ResidencyStatusID
      , pell.Code
      , pell.AwardAmount
      , pell.TransmitAmount
    ORDER BY sch.StudentPersonID
      , sch.Term
  END
END
