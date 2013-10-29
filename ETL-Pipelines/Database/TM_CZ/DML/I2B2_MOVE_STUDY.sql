CREATE OR REPLACE PROCEDURE tm_cz.I2B2_MOVE_STUDY(VARCHAR(ANY), VARCHAR(ANY), INTEGER)
RETURNS INTEGER
EXECUTE AS OWNER
LANGUAGE NZPLSQL AS
BEGIN_PROC
DECLARE
	trial_id ALIAS FOR $1;
	topNode ALIAS FOR $2;
	currentJobID ALIAS FOR $3;
BEGIN

  root_node			varchar(2000);
  root_level		int;
  topLevel			int;
  TrialId			varchar(100);
  old_Path			varchar(2000);
  newPath			varchar(2000);
  new_study_name	varchar(200);
  old_study_name	varchar(200);
  pExists		int;
 
  --Audit variables
  newJobFlag INTEGER(1);
  databaseName VARCHAR(100);
  procedureName VARCHAR(100);
  jobID number(18,0);
  stepCt number(18,0);
  
 -- invalid_TrialId		exception;
 -- invalid_topNode		exception;
  
 	TrialId := upper(trial_id);
	stepCt := 0;
	
	--Set Audit Parameters
	newJobFlag := 0; -- False (Default)
	jobID := currentJobID;

--	SELECT sys_context('USERENV', 'CURRENT_SCHEMA') INTO databaseName FROM dual;
--	procedureName := $$PLSQL_UNIT;
	select CURRENT_CATALOG into databaseName;
	select I2B2_SECURE_STUDY into procedureName;  	
	
	--Audit JOB Initialization
	--If Job ID does not exist, then this is a single procedure run and we need to create it
	IF(jobID IS NULL or jobID < 1)
	THEN
		newJobFlag := 1; -- True
	call tm_cz.czx_start_audit (procedureName, databaseName, jobID);
	END IF;

	stepCt := stepCt + 1;
	call tm_cz.czx_write_audit(jobId,databaseName,procedureName,'Start '||procedureName,0,stepCt,'Done'); 

	--	check if study exists
	
	select count(*) into pExists
	from i2b2metadata.i2b2
	where sourcesystem_cd = TrialId;
	
	if pExists = 0
		then raise invalid_TrialId;
	end if;
	
	--	get current top node for study
	
	select min(c_fullname) into old_path
	from i2b2metadata.i2b2
	where sourcesystem_cd = TrialId;
	
	--	get current study name for study
	
	select c_name into old_study_name
	from i2b2metadata.i2b2
	where c_fullname = old_path;
	
	--	check that topNode is not null or %
	
	if coalesce(topNode,'') = '' or topNode = '%' then
		raise invalid_topNode;
	end if;
	
	newPath := REGEXP_REPLACE('\' || topNode || '\','(\\){2,}', '\');
	select length(newPath)-length(replace(newPath,'\','')) into topLevel; -- from dual;
	
	if topLevel < 3 then
		raise invalid_topNode;
	end if;
	
	--	get root_node of new path
	
	select parse_nth_value(newPath, 2, '\') into root_node; -- from dual;
	
	select count(*) into pExists
	from i2b2metadata.table_access
	where c_name = root_node;
		
	--	add root_node if it doesn't exist
	
	if pExists = 0 then
		call tm_cz.i2b2_add_root_node(root_node,jobId);
	end if;
		
	select c_hlevel into root_level
	from i2b2metadata.table_access
	where c_name = root_node;
		
	--	get study_name from new path, doesn't have to be the same as the existing study name
	
	select parse_nth_value(newPath, topLevel, '\') into new_study_name; -- from dual;
	stepCt := stepCt + 1;
	call tm_cz.czx_write_audit(jobId,databaseName,procedureName,'study_name: ' || new_study_name,0,stepCt,'Done');
		
    --CONCEPT DIMENSION
	update i2b2demodata.concept_dimension
	set CONCEPT_PATH = replace(concept_path, old_path, newPath)
	where concept_path like old_path || '%';
	stepCt := stepCt + 1;
	call tm_cz.czx_write_audit(jobId,databaseName,procedureName,'Update concept_dimension with new path',SQL%ROWCOUNT,stepCt,'Done'); 
	COMMIT;
    
	--I2B2
	update i2b2
	set c_fullname = replace(c_fullname, old_path, newPath)
		,c_dimcode = replace(c_fullname, old_path, newPath)
		,c_tooltip = replace(c_fullname, old_path, newPath)
		,c_hlevel =  (length(replace(c_fullname, old_path, newPath)) - nvl(length(replace(replace(c_fullname, old_path, newPath), '\')),0)) / length('\') - 2 + root_level
		,c_name = parse_nth_value(replace(c_fullname, old_path, newPath),(length(replace(c_fullname, old_path, newPath))-length(replace(replace(c_fullname, old_path, newPath),'\',null))),'\') 
	where c_fullname like old_path || '%';
	stepCt := stepCt + 1;
	call tm_cz.czx_write_audit(jobId,databaseName,procedureName,'Update i2b2 with new path',SQL%ROWCOUNT,stepCt,'Done'); 
	COMMIT;
		
	--	concept_counts
		
	update i2b2demodata.concept_counts
	set concept_path = replace(concept_path, old_path, newPath)
	   ,parent_concept_path = replace(parent_concept_path, old_path, newPath)
	where concept_path like old_path || '%';
	stepCt := stepCt + 1;
	call tm_cz.czx_write_audit(jobId,databaseName,procedureName,'Update concept_counts pass 1',SQL%ROWCOUNT,stepCt,'Done'); 
	COMMIT;
	
	--	update parent_concept_path for new_path (replace doesn't work)
	
	update i2b2demodata.concept_counts 
	set parent_concept_path=ltrim(SUBSTR(concept_path, 1,instr(concept_path, '\',-1,2)))
	where concept_path = newPath;
	stepCt := stepCt + 1;
	call tm_cz.czx_write_audit(jobId,databaseName,procedureName,'Update concept_counts pass 2',SQL%ROWCOUNT,stepCt,'Done'); 
	COMMIT;
	
	--	update modifier_dimension if new_study_name not equal old_study_name
	
	if new_study_name != old_study_name then
		update i2b2demodata.modifier_dimension
		set modifier_path='\Study\' || new_study_name || '\'
		   ,name_char=new_study_name
		where modifier_cd = 'STUDY:' || TrialId;
		stepCt := stepCt + 1;
		call tm_cz.czx_write_audit(jobId,databaseName,procedureName,'Update study name in modifier_dimension',SQL%ROWCOUNT,stepCt,'Done'); 
		COMMIT;
	end if;	
	
	--	fill in any upper levels
	
	call tm_cz.i2b2_fill_in_tree(null, newPath, jobID);
	
	call tm_cz.i2b2_load_security_data(jobId);
	
	IF newJobFlag = 1
	THEN
		call tm_cz.czx_end_audit (jobID, 'SUCCESS');
	END IF;

	EXCEPTION
	when invalid_topNode then
		stepCt := stepCt + 1;
		call tm_cz.czx_write_audit(jobId,databaseName,procedureName,'Path specified as topNode must contain at least 2 nodes',0,stepCt,'Done');	
		call tm_cz.czx_error_handler (jobID, procedureName);
		call tm_cz.czx_end_audit (jobID, 'FAIL');
	when invalid_TrialId then
		stepCt := stepCt + 1;
		call tm_cz.czx_write_audit(jobId,databaseName,procedureName,'Trial Id '||trial_id||' does not exist',0,stepCt,'Done');	
		call tm_cz.czx_error_handler (jobID, procedureName);
		call tm_cz.czx_end_audit (jobID, 'FAIL');
		--rtnCode := 16;
	WHEN OTHERS THEN
		--Handle errors.
		call tm_cz.czx_error_handler (jobID, procedureName);
		--End Proc
		call tm_cz.czx_end_audit (jobID, 'FAIL');
  
END;
END_PROC;
