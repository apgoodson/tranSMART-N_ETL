  CREATE OR REPLACE PROCEDURE TM_CZ.I2B2_DELETE_1_NODE
(
  varchar(2000)
 ,bigint
) RETURNS CHARACTER VARYING(ANY)
LANGUAGE NZPLSQL AS
BEGIN_PROC
/*************************************************************************
* Copyright 2008-2012 Janssen Research & Development, LLC.
*
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
* http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
******************************************************************/
Declare
	--	Alias for parameters
	input_path alias for $1;
	currentJobID alias for $2;
 
	--Audit variables
	newJobFlag int4;
	databaseName VARCHAR(100);
	procedureName VARCHAR(100);
	jobID numeric(18,0);
	stepCt numeric(18,0);

begin
  --Set Audit Parameters
	newJobFlag := 0; -- False (Default)
	jobID := currentJobID;

	databaseName := 'TM_CZ';
	procedureName := 'I2B2_FILL_IN_TREE';

	--Audit JOB Initialization
	--If Job ID does not exist, then this is a single procedure run and we need to create it
	IF(jobID IS NULL or jobID < 1)
	THEN
		newJobFlag := 1; -- True
		-- select tm_cz.czx_start_audit (procedureName, databaseName) into jobId;
	END IF;
    	
  stepCt := 0;  
  if coalesce(input_path,'') = ''  or input_path = '%'
	then 
		-- call tm_cz.czx_write_audit(jobId,databaseName,procedureName,'Path missing or invalid',0,stepCt,'Done'); 
  else
    --I2B2
    DELETE 
      FROM i2b2demodata.OBSERVATION_FACT 
    WHERE 
      concept_cd IN (SELECT C_BASECODE FROM i2b2metadata.I2B2 WHERE C_FULLNAME = input_path);
	stepCt := stepCt + 1;
	-- call czx_write_audit(jobId,databaseName,procedureName,'Delete data for node from I2B2DEMODATA observation_fact',SQL%ROWCOUNT,stepCt,'Done');

      --CONCEPT DIMENSION
    DELETE 
      FROM i2b2demodata.CONCEPT_DIMENSION
    WHERE 
      CONCEPT_PATH = input_path;
	stepCt := stepCt + 1;
	-- call czx_write_audit(jobId,databaseName,procedureName,'Delete data for node from I2B2DEMODATA concept_dimension',SQL%ROWCOUNT,stepCt,'Done');
    
      --I2B2
      DELETE
        FROM i2b2metadata.i2b2
      WHERE 
        C_FULLNAME = input_path;
	stepCt := stepCt + 1;
	-- call czx_write_audit(jobId,databaseName,procedureName,'Delete data for node from I2B2METADATA i2b2',SQL%ROWCOUNT,stepCt,'Done');

  --i2b2_secure
      DELETE
        FROM i2b2metadata.i2b2_secure
      WHERE 
        C_FULLNAME = input_path;
	stepCt := stepCt + 1;
	-- call czx_write_audit(jobId,databaseName,procedureName,'Delete data for node from I2B2METADATA i2b2_secure',SQL%ROWCOUNT,stepCt,'Done');

  --concept_counts
      DELETE
        FROM i2b2demodata.concept_counts
      WHERE 
        concept_path = input_path;
	stepCt := stepCt + 1;
	-- call czx_write_audit(jobId,databaseName,procedureName,'Delete data for node from I2B2DEMODATA concept_counts',SQL%ROWCOUNT,stepCt,'Done');

  END IF;
  
    ---Cleanup OVERALL JOB if this proc is being run standalone
  IF newJobFlag = 1
  THEN
    -- call czx_end_audit (jobID, 'SUCCESS');
  END IF;

  EXCEPTION
  WHEN OTHERS THEN
	raise notice 'error: %', SQLERRM;
    --Handle errors.
    -- call czx_error_handler (jobID, procedureName);
    --End Proc
    -- call czx_end_audit (jobID, 'FAIL');    
END;
END_PROC;

 
