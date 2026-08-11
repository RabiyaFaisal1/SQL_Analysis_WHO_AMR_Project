------------------------------------------------------------------------------------------------------------------------------ 
-- STEP 1: Exploring the data initially 
USE glass_amr;
SHOW TABLES;
-- Determining the structure of resistance_snapshot_2023 column so we get idea of column names
DESCRIBE resistance_snapshot_2023;
-- Determining the structure of resistance_timeseries column so we get idea of column names
DESCRIBE resistance_timeseries;
-- Viewing the top 10 rows
SELECT * 
FROM resistance_timeseries
LIMIT 10;
-- Resistance_snapshot
SELECT  * 
FROM resistance_snapshot_2023
LIMIT 10;
------------------------------------------------------------------------------------------------------------------------------ 
-- STEP 2: Creating a staging tables so our initial data is safely stored 
CREATE TABLE resistance_snapshot_2023_staging
LIKE resistance_snapshot_2023;
CREATE TABLE resistance_timeseries_staging
LIKE resistance_timeseries;
-- Inserting data into new table 
INSERT INTO resistance_snapshot_2023_staging
SELECT * 
FROM resistance_snapshot_2023;
INSERT INTO resistance_timeseries_staging
SELECT * 
FROM resistance_timeseries;
-----------------------------------------------------------------------------------------------------------------------------
-- STEP 3:  Cleaning Steps
-- 1. Checking for missing values
-- 2. Checking for duplicates
-- 3. Standardization- Checking for inconsistent spellings/naming
-- 4. Checking for relatively small sample sizes
-- 5. Checking for resistance percentage within a valid range(0-100)
 ------------------------------------------------------------------------------
 -- 1. Checking for missing values
 -- 1a.Checking for missing values from resistance_snapshot_2023
 SELECT *
 FROM resistance_snapshot_2023_staging 
 WHERE ResistancePercentage is null -- numeric column: Null check only
 OR PathogenName is null or PathogenName = ''
 OR Iso3 is null or Iso3 = '';
 #checking these 3 columns because:
 -- ResistancePercentage is the actual number we are analyzing so without it row is useless
 -- A row with no pathogen cannot be grouped so it will be of no use
 -- Iso 3 is link to the country without it we cannot tell from where the disease came from and cannot join it with tables.
 
 -- 1b. Checking for missing values in resistance_timeseries 
 SELECT *
 FROM resistance_timeseries_staging
 WHERE PercentResistant is null -- numeric column: Null check only
 OR PathogenName is null or PathogenName = ''
 OR Iso3 is null or Iso3 = '';
 
-- #2. Checking for duplicates
-- 2a. Checking for duplicates for resistance_snapshot_2023
WITH duplicate_cte AS
(
SELECT *,
   Row_Number() 
   OVER(PARTITION BY AntibioticName, PathogenName, Iso3
   ORDER BY Iso3) AS row_num
FROM resistance_snapshot_2023_staging
)
 SELECT*
 FROM duplicate_cte WHERE row_num > 1;

-- 2b. Checking for duplicates for resistance_timeseries
with duplicate_cte1 as
(
SELECT *,
row_number() 
OVER(PARTITION BY Iso3,  PathogenName , AbTargets, `Year`
ORDER BY Iso3) AS row_numb
FROM resistance_timeseries_staging
)
SELECT *
FROM duplicate_cte1 where row_numb > 1;

-- 3. Standardization- Checking for inconsistent spellings/naming
-- 3a. For snapshot table
SELECT DISTINCT PathogenName
FROM resistance_snapshot_2023_staging;
SELECT DISTINCT AntibioticName 
FROM resistance_snapshot_2023_staging;
SELECT DISTINCT CountryTerritoryArea
FROM resistance_snapshot_2023_staging;

-- 3b. For timeseries table
SELECT DISTINCT PathogenName 
FROM resistance_timeseries_staging;
SELECT DISTINCT AbTargets 
FROM resistance_timeseries;
SELECT DISTINCT CountryTerritoryArea
FROM resistance_timeseries_staging;
-- PROBLEM: SELECT DISTINCT displayed a few country names that were not the correct characters, but were broken ones.
-- Step 1 Recheck: Finding the broken names.
SELECT DISTINCT CountryTerritoryArea
FROM resistance_snapshot_2023_staging
WHERE CountryTerritoryArea LIKE '%rkiye%' OR CountryTerritoryArea LIKE '%voire%';
-- Step 2 — Fixing them
UPDATE resistance_snapshot_2023_staging
SET CountryTerritoryArea = 'Türkiye'
WHERE CountryTerritoryArea LIKE '%rkiye%';
UPDATE resistance_snapshot_2023_staging
SET CountryTerritoryArea = "Côte d'Ivoire"
WHERE CountryTerritoryArea LIKE '%voire%';

UPDATE resistance_timeseries_staging
SET CountryTerritoryArea = 'Turkiye'
WHERE CountryTerritoryArea LIKE '%rkiye%';
UPDATE resistance_timeseries_staging
SET CountryTerritoryArea = "Côte d'Ivoire"
WHERE CountryTerritoryArea LIKE '%voire%';
-- Step 3 – Rechecking again, to confirm the fix has been successfull
SELECT DISTINCT CountryTerritoryArea
FROM resistance_snapshot_2023_staging
WHERE CountryTerritoryArea LIKE '%rkiye%' OR CountryTerritoryArea LIKE '%voire%';

-- 4. Checking for relatively small sample sizes- flagging rows with fewer than 10 isolates as at this stage WHO itself resistance% unreliable
-- 4a. Snapshot table
SELECT*
FROM resistance_snapshot_2023_staging
WHERE InterpretableAST < 10;

-- 4b. Timeseries table
SELECT *
FROM resistance_timeseries_staging
WHERE InterpretableAST < 10;
-- InterpretableAST: Number of test results WHO could actually use & interpret

-- 5. Checking for resistance percentage within a valid range(0-100)
-- 5a. Snapshot table
SELECT *
FROM resistance_snapshot_2023_staging
WHERE ResistancePercentage < 0 or ResistancePercentage > 100;
-- 5b. Timeseries table
SELECT *
FROM resistance_timeseries_staging
WHERE PercentResistant < 0 or PercentResistant > 100;
------------------------------------------------------------------------------------------------------------------------------ 
-- STEP 4: Explanatory Data Analysis- what the data is telling use
-- BUSSINESS QUESTION 1: Which pathogen antibiotic has highest resistance rate in 2023?
SELECT 
   PathogenName,
   AntibioticName,
   CountryTerritoryArea,
   InterpretableAST,
   ResistancePercentage
FROM resistance_snapshot_2023_staging
ORDER BY ResistancePercentage DESC
LIMIT 10;
-- ANSWER: SO In 2023, 10 pathogen-antibiotic-country combinations were identified which were 100% resistant, covering a range of pathogens
-- (Acinetobacter, Klebsiella pneumoniae, E. coli) and range of antibiotics (100% resistance to multiple antibiotics not a single case).
-- Sample size behind these results ranged from 11 to 63 tested single cases hence meeting the minimum reliability threshold, though smaller sample
-- within that range should still be read with some caution. 

-- BUSSINESS QUESTION 2: Which pathogen has highest average resistance rate across all countires and antibiotics tested in 2023?
SELECT PathogenName,
ROUND(AVG(ResistancePercentage), 2) AS avg_resistance
FROM resistance_snapshot_2023_staging
GROUP BY PathogenName
ORDER BY avg_resistance DESC;
-- ANSWER:Acinetobacter spp. and Klebsiella pneumoniae showed the highest average resistance rate (42.77% & 42.48 respectively) among all 
-- countries/antibiotics tested in 2023. (42.48%). E. coli is significantly lower at 32.56%, as is Streptococcus pneumoniae (12.61%) 
-- and Salmonella spp. However, there is a significant difference in average resistance between the two most difficult-to-treat
-- pathogens and all other pathogens, with (10.08%) exhibiting much lower average resistance.

-- BUSSINESS QUESTION 3: For each pathogen which country has the highest resistance rate?
WITH ranked_countries AS
( SELECT PathogenName,
CountryTerritoryArea,
ResistancePercentage,
RANK() OVER(PARTITION BY PathogenName 
   ORDER BY ResistancePercentage DESC) AS Ranked_resistance
FROM resistance_snapshot_2023_staging
) 
SELECT PathogenName,
CountryTerritoryArea,
ResistancePercentage
FROM ranked_countries
WHERE Ranked_resistance = 1
ORDER BY PathogenName
;
-- ANSWER:The country with the most resistance for each pathogen: Bangladesh and North Macedonia both have 100% resistance against
-- Acinetobacter spp.; Uganda and Côte d'Ivoire are tied for 100% resistance against E. coli; seven countries 
-- (Maldives, Malawi, Côte d'Ivoire, Zambia, Lebanon, Kosovo, Yemen) are tied with 100% resistance against Klebsiella pneumoniae;
-- Iraq leads with 95.3% resistance against Salmonella spp.; and the Democratic Republic of Congo leads with 97.9% resistance 
--  against Streptococcus pneumoniae. 
-- Some pathogens have exactly 100% and that's why we used RANK() and not ROW_NUMBER() as ROW_NUMBER() would only have shown 
-- one of the top pathogens as rank 1, but RANK() would have shown them all as rank

-- BUSSINESS QUESTION 4: What is the year over year change in resistance for each pathogen from 2018 and 2023?
WITH yearly_avg AS
(SELECT 
       PathogenName, 
       `Year`,
       ROUND(AVG(PercentResistant),2) AS Average_resistance
FROM resistance_timeseries_staging
GROUP BY PathogenName, `Year`
)
SELECT
       PathogenName, 
       `Year`,
       Average_resistance,
       LAG(Average_resistance) OVER(PARTITION BY PathogenName
       ORDER BY `Year`) AS Prev_year_resistance,
       Average_resistance - LAG(Average_resistance) OVER(PARTITION BY PathogenName
       ORDER BY `Year`) AS Year_over_year_change
FROM yearly_avg
ORDER BY PathogenName,`Year`;   
       
-- ANSWER: Acinetobacter spp. had a general increasing trend from 2018 to 2022 from 46.55% to 55.23%. However, there was a slight decrease in 
-- resistance in 2023, dropping by 0.67 percentage point. The overall trend is positive, however, the trend is not continually increasing.
-- There was more variability from year to year for E. coli. Between 2019 and 2020, resistance grew; it decreased by 3.45 percentage points in 2021, 
-- but rose once more in 2023. It is relatively small net increase, and there are a number of intermediate fluctuations which are not obvious.
-- For Klebsiella pneumoniae, however, the pattern was reversed, with a downward trend for a few years, before a strong rebound in 2023. Resistance
-- fell from 55.10% to 50.96% before increasing by 4.18 percentage points in 2023 to 55.14%. 
-- Overall increase over 2018-2023 does not fully show the trajectory of the pathogen.
-- Between 2021 and 2022, Salmonella spp. levels have dropped, but they are rising during 2022 and 2023. Its resistance increased from 8.79% 
-- in 2018 to 9.19% in 2023. A small overall rise is seen in the unrounded figures, which is not what was found in the previous study, as both 
-- were rounded at 9%.
-- Streptococcus pneumoniae was the most volatile organism. Resistance has been fairly steady from 2020 to 2021, rising by 5.93 percentage points 
-- to 10.22% in 2022. This then dropped to 1.94% in 2023, representing a reduction of 8.28 percentage points. 
-- The +5.93 percentage-point increase in 2022 was the largest single-year increase among the five pathogens, while the −8.28 percentage-point change
-- in 2023 was the largest single-year decrease.

-- BUSSINESS QUESTION 5: Which countries perform the most testing? And is there any relationship between testing volume and resistance?
SELECT CountryTerritoryArea,
SUM(TotalSpecimenIsolates) AS Total_isolates_tested,
ROUND(AVG(PercentResistant),2) AS Average_resistance,
RANK() OVER (ORDER BY SUM(TotalSpecimenIsolates) DESC) AS Testing_Volume
FROM resistance_timeseries_staging
GROUP BY CountryTerritoryArea
ORDER BY Total_isolates_tested DESC
LIMIT 15;
-- ANSWER The volume of testing is very different in the different countries. The highest testing volume was in Japan, with over 4.4 million of 
-- them tested, and the average resistance rate was a relatively low of 3.97%. By contrast, countries that were testing significantly less had 
-- much higher resistances. For instance, in India, the average resistance rate was 67.4% as 511,000 isolates were tested, while in Iran, 
-- 39,000 isolates were tested with an average resistance rate of 61.18%. The Russian Federation was the lowest country tested with total about
--  19,700 isolates with the highest average resistance rate of 85.87%. In general, there is no obvious relationship between testing volume and
--  resistance based on their country-level comparison. Increased number of isolates tested does not necessarily equal increased resistance or 
-- increased susceptibility.Japan is an example of this, as it has a very large testing volume, but a low resistance rate; several countries 
-- with lower testing volumes reported much higher resistance. The results obtained need to be interpreted with some caution as countries with 
-- lower numbers of tests may have less stable or representative resistance estimates, even if the minimum number of 10 tests is reached.


-- BUSSINESS QUESTION 6: Comparing from 2018 to 2023 which pathogen's resistance rate worsened the most and which reduced?
WITH Yearly_resistance AS
(SELECT
     PathogenName,
     `Year`,
     ROUND(AVG(PercentResistant)) AS Average_resistance
FROM resistance_timeseries_staging
GROUP BY  PathogenName,`Year`
),
Change_2018_2023 AS
(SELECT
	   PathogenName,
       MAX(CASE
               WHEN `Year` = 2018 THEN Average_resistance
	       END) AS Resistance_2018,
	   MAX(CASE
               WHEN `Year` = 2023 THEN Average_resistance
           END) AS Resistance_2023,
	   MAX(CASE
               WHEN `Year` = 2023 THEN Average_resistance
	       END) -
		MAX(CASE
               WHEN `Year` = 2018 THEN Average_resistance
           END) AS Point_change
FROM Yearly_resistance
GROUP BY PathogenName
)
SELECT 
      PathogenName,
      Resistance_2018,
      Resistance_2023,
      Point_change,
RANK() OVER(ORDER BY Point_change DESC) AS Worsened_rank
FROM Change_2018_2023
ORDER BY Point_change DESC;
-- ANSWER: Acinetobacter spp. recorded the highest growth of 55% in 2023 compared to 47% in 2018, representing an increase of 8 percentage points. 
-- This showed the highest increase of the pathogens analysed.
-- Klebsiella pneumoniae also rose, by 2% from 53% to 55%.
-- Salmonella spp. showed no change, remaining at 9% in both 2018 and 2023.
-- E. coli resistance rose slightly from 36% to 37%, a change of only 1-percentage-point
-- Only one pathogen was improving with resistance dropping from 4% to 2% or a 2 percentage-point decrease, Streptococcus pneumoniae
------------------------------------------------------------------------------------------------------------------------------ 
