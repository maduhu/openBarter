/*

STOCK MOVEMENTS
*********************
addaccount	quality[stock.np] +=qtt	stockA[owner] +=qtt
subaccount	quality[stock.np] -=qtt	stockA[owner] -=qtt
create stock	stockA[owner]  -=qtt	stockS[owner] +=qtt
create draft	stockS[owner]  -=qtt	stockD[owner] +=qtt

execut draft	stockD[owner]  -=qtt	
		stockA[newowner] =+qtt (commit.sid_src -> commit.sid_dst)
		
refuse draft	stockD[owner]  -=qtt	
		stockS[owner] +=qtt  (commit.sid_dst -> commit.sid_src)
		
delete bid	stockS[owner]  -=qtt		stockA[owner] +=qtt

*/
create table ob_tconst(
	name text,
	value	int,
	PRIMARY KEY (name),
    	UNIQUE(name)
);
INSERT INTO ob_tconst (name,value) VALUES ('obCMAXCYCLE',8);
INSERT INTO ob_tconst (name,value) VALUES ('MAINTENANCE',0);
CREATE FUNCTION ob_get_const(_name text) RETURNS int AS $$
DECLARE
	_ret text;
BEGIN
	SELECT value INTO _ret FROM ob_tconst WHERE name=_name;
	RETURN _ret;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION ob_get_const(text) TO market;
--------------------------------------------------------------------------------
CREATE FUNCTION ob_fset_maintenance(_b bool) RETURNS void AS $$
DECLARE
	_v int;
BEGIN
	IF(_b) THEN 
		IF(ob_get_const('MAINTENANCE')=1) THEN
			RAISE INFO 'Already in maintenance mode';
		END IF;
		_v=1;
	ELSE 
		IF(ob_get_const('MAINTENANCE')=0) THEN
			RAISE INFO 'Already in non maintenance mode';
		END IF;
		_v= 0;
	END IF;
	UPDATE ob_tconst SET value=_v WHERE name='MAINTENANCE';
	RETURN;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION ob_fset_maintenance(bool) TO market;
--------------------------------------------------------------------------------
CREATE FUNCTION ob_fcan_exec() RETURNS int AS $$
DECLARE
	_v int;
BEGIN
	SELECT value INTO _v FROM ob_tconst WHERE name='MAINTENANCE';
	IF(_v = 1) THEN 
		RAISE EXCEPTION 'Maitenance in process';
	ELSE RETURN 1;
	END IF;
END; 
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
-- ob_ftime_updated 
--	trigger before insert on tables
--------------------------------------------------------------------------------
CREATE FUNCTION ob_ftime_updated() 
	RETURNS trigger AS $$
BEGIN
	IF (TG_OP = 'INSERT') THEN
		NEW.created := statement_timestamp();
	ELSE 
		NEW.updated := statement_timestamp();
	END IF;
	RETURN NEW;
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
comment on FUNCTION ob_ftime_updated() is 
'trigger updating fields created and updated';

--------------------------------------------------------------------------------
-- 
--------------------------------------------------------------------------------
CREATE FUNCTION _create_role_market() RETURNS int AS $$
DECLARE
	_rol text;
BEGIN
	SELECT rolname INTO _rol FROM pg_roles WHERE rolname='market';
	IF NOT FOUND THEN
		CREATE ROLE market;
	END IF;
	RETURN 0;
END; 
$$ LANGUAGE PLPGSQL;

SELECT _create_role_market();
DROP FUNCTION _create_role_market();

--------------------------------------------------------------------------------
-- 
--------------------------------------------------------------------------------
CREATE FUNCTION _reference_time_trig(_table text) RETURNS int AS $$
DECLARE
	_trigg text;
BEGIN
	_trigg := 'trig_befa_' || _table;
	EXECUTE 'CREATE TRIGGER ' || _trigg || ' BEFORE INSERT
		OR UPDATE ON ' || _table || ' FOR EACH ROW
		EXECUTE PROCEDURE ob_ftime_updated()' ; 
	EXECUTE 'GRANT SELECT ON TABLE ' || _table || ' TO market';
	-- EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE ON ' || _table || ' TO MARKET';
	RETURN 0;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;



CREATE FUNCTION _reference_time(_table text) RETURNS int AS $$
DECLARE
	_res int;
BEGIN
	
	EXECUTE 'ALTER TABLE ' || _table || ' ADD created timestamp';
	EXECUTE 'ALTER TABLE ' || _table || ' ADD updated timestamp';
	select _reference_time_trig(_table) into _res;
	RETURN 0;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;


--------------------------------------------------------------------------------
-- OB_TQUALITY
--------------------------------------------------------------------------------
-- create sequence ob_tquality_id_seq;
create table ob_tquality (
    id bigserial UNIQUE not NULL,
    name text not NULL,
    qtt bigint default 0,
    PRIMARY KEY (id),
    UNIQUE(name)
);
comment on table ob_tquality is 
'description of qualities';
alter sequence ob_tquality_id_seq owned by ob_tquality.id;
create index tquality_name_idx on ob_tquality(name);
SELECT _reference_time('ob_tquality');

	
--------------------------------------------------------------------------------
-- OB_TOWNER
--------------------------------------------------------------------------------
-- create sequence ob_towner_id_seq;
create table ob_towner (
    -- id int8 UNIQUE not NULL default nextval('ob_towner_id_seq'),
    id bigserial UNIQUE not NULL,
    name text not NULL,
    PRIMARY KEY (id),
    UNIQUE(name)
);
comment on table ob_towner is 
'description of owners of values';
alter sequence ob_towner_id_seq owned by ob_towner.id;
create index towner_name_idx on ob_towner(name);
SELECT _reference_time('ob_towner');
insert into ob_towner (name) values ('market');

--------------------------------------------------------------------------------
-- OB_TSTOCK
-- stores a value owned.
--------------------------------------------------------------------------------

create type ob_ystock as enum ('Account','Stock','Draft');
-- create sequence ob_tstock_id_seq;
create table ob_tstock (
    id bigserial UNIQUE not NULL,
    own int8 references ob_towner(id) on update cascade 
	on delete restrict not NULL,
		-- owner can be deleted only if he has not stock
    qtt bigint not NULL, -- 64 bits
    np int8 references ob_tquality(id) on update cascade 
	on delete restrict not NULL,
    type ob_ystock,
    PRIMARY KEY (id),
    
    CHECK ( (type='Account' and (own=1) and (qtt < 0 or qtt = 0)) 
    	-- market has only stock.qtt <=0
    	or (type='Account' and (own!=1) and (qtt > 0 or qtt = 0))
    	-- owners have only stock.qtt >=0
    	or ((type='Stock' or type='Draft') and (qtt > 0 or qtt = 0))),
    	
    -- only one account for each (own,np)
    EXCLUDE (own with =,np with =,type with =) WHERE (type='Account')
);
comment on table ob_tstock is 'description of values';
comment on column ob_tstock.own is 'refers to the owner';
comment on column ob_tstock.qtt is 'quantity of the value';
comment on column ob_tstock.np is 'refers to the quality of the value';

alter sequence ob_tstock_id_seq owned by ob_tstock.id;
create index tstock_own_idx on ob_tstock(own);
create index tstock_np_idx on ob_tstock(np);
SELECT _reference_time('ob_tstock');

--------------------------------------------------------------------------------
-- OB_TNOEUD
--------------------------------------------------------------------------------
-- create sequence ob_tnoeud_id_seq;

create table ob_tnoeud ( -- bid
    id bigserial UNIQUE not NULL,
    sid int8 references ob_tstock(id) on update cascade 
	on delete cascade not NULL , 
    nr int8 references ob_tquality(id) on update cascade 
	on delete cascade not NULL ,
    qtt_prov int8,
    qtt_requ int8, 
    PRIMARY KEY (id)
);

comment on table ob_tnoeud is 'description of bids';
comment on column ob_tnoeud.sid is 'refers to the stock offered';
comment on column ob_tnoeud.nr is 'refers to quality required';
comment on column ob_tnoeud.qtt_prov is 
'used to express omega, but not the quantity offered';
comment on column ob_tnoeud.qtt_requ is 
'used to express omega';

alter sequence ob_tnoeud_id_seq owned by ob_tnoeud.id;
create index tnoeud_sid_idx on ob_tnoeud(sid);
create index tnoeud_nr_idx on ob_tnoeud(nr);
SELECT _reference_time('ob_tnoeud');

--------------------------------------------------------------------------------
-- OB_TFORBIT
--------------------------------------------------------------------------------
-- create sequence ob_tnoeud_id_seq;

create table ob_trefused ( -- bid
    x int8 references ob_tnoeud(id) on update cascade 
	on delete cascade not NULL , 
    y int8 references ob_tnoeud(id) on update cascade 
	on delete cascade not NULL ,
    PRIMARY KEY (x,y),UNIQUE(x,y)
);

comment on table ob_trefused is 'list of relations refused';



--------------------------------------------------------------------------------
-- OB_TDRAFT
-- draft		status
-- created		D<-
-- accepted		A<-D	all commit are accepted
-- refused		R<-D	one (or more) commit is refused
--------------------------------------------------------------------------------

create type ob_ydraft as enum ('Draft','Accepted','Refused');
create table ob_tdraft (
    id bigserial UNIQUE not NULL, -- never 0, but 1..n for n drafts
    status ob_ydraft,
    nbnoeud int2,
    delay int8, 
    PRIMARY KEY(id)
);
comment on table ob_tdraft is 'description of draft agreements';
SELECT _reference_time('ob_tdraft');

--------------------------------------------------------------------------------
-- OB_TCOMMIT
--------------------------------------------------------------------------------
-- create sequence ob_tcommit_id_seq;
create table ob_tcommit (
	id bigserial UNIQUE not NULL,
	did int8 references ob_tdraft(id) 
		on update cascade on delete cascade,
	bid int8 references ob_tnoeud(id) 
		on update cascade,
	sid_src int8 references ob_tstock(id) 
		on update cascade,
	sid_dst int8 references ob_tstock(id) 
		on update cascade,
	wid	int8 references ob_towner(id) 
		on update cascade,
	flags int4, 	-- [0] draft did accepted by owner wid,
			-- [1] draft did refused by owner wid,
			-- [2] exhausted: stock.qtt=fluxarrondi for sid
	PRIMARY KEY(id)
);
comment on table ob_tcommit is 
'description of an element of the draft agreement refered by ob_tcommit.did';
comment on column ob_tcommit.did is 'refers to the draft containing this commit';
comment on column ob_tcommit.bid is 'refers to the bid used to create this commit';
comment on column ob_tcommit.wid is 'refers to the author of the bid';
comment on column ob_tcommit.sid_src is 'stock[sid_src] refers to the value offered by the bid';
comment on column ob_tcommit.sid_dst is 'stock[sid_dst] is the value provided';
comment on column ob_tcommit.flags is 
'flags[0] is set when accepted, flags[1] is set when refused,flags[2] is set when stock.qtt=fluxarrondi for stock[sid]';

alter sequence ob_tcommit_id_seq owned by ob_tcommit.id;
create index tcommit_did_idx on ob_tcommit(did);
create index tcommit_sid_src_idx on ob_tcommit(sid_src);
create index tcommit_sid_dst_idx on ob_tcommit(sid_dst);

--------------------------------------------------------------------------------
-- OB_TMVT
--	An owner can be deleted only if he owns no stocks.
--	When it is deleted, it's movements are deleted
--------------------------------------------------------------------------------
-- create sequence ob_tmvt_id_seq;
create table ob_tmvt (
        id bigserial UNIQUE not NULL,
    	did int8 references ob_tmvt(id) 
		on delete cascade default NULL, 
    	-- References the first mvt of a draft.
		-- NULL when movement add_account()
		-- not NULL for a draft executed. 
	own_src int8 references ob_towner(id) 
		on update cascade on delete cascade not null, 
	own_dst int8  references ob_towner(id) 
		on update cascade on delete cascade not null,
	qtt bigint check (qtt >0 or qtt = 0) not null,
	nat int8 references ob_tquality(id) 
		on update cascade on delete cascade not null
);
comment on table ob_tmvt is 
'records a change of ownership';
comment on column ob_tmvt.did is 
	'refers to the draft whose execution created this movement';
comment on column ob_tmvt.own_src is 
	'old owner';
comment on column ob_tmvt.own_dst is 
	'new owner';
comment on column ob_tmvt.qtt is 
	'quantity of the value';
comment on column ob_tmvt.nat is 
	'quality of the value';

create index tmvt_did_idx on ob_tmvt(did);
-- create index tmvt_src_idx on ob_tmvt(src);
-- create index tmvt_dst_idx on ob_tmvt(dst);
create index tmvt_nat_idx on ob_tmvt(nat);
create index tmvt_own_src_idx on ob_tmvt(own_src);
create index tmvt_own_dst_idx on ob_tmvt(own_dst);
SELECT _reference_time('ob_tmvt');


/*******************************************/
 -- VIEWS
/*******************************************/
--------------------------------------------------------------------------------
-- ob_vowned
--------------------------------------------------------------------------------
/* List of values owned by users GROUP BY s.own,s.nf,q.name,o.name
	view
		returns qtt owned for each (quality,own).
			qname:		quality.name
			owner: 	owner.name
			qtt:		sum(qtt) for this (quality,own)
			created:	min(created)
			updated:	max(updated?updated:created)
	usage:
		SELECT * FROM ob_vowned WHERE owner='toto'
			total values owned by the owner 'toto'
		SELECT * FROM ob_vowned WHERE qown='banquedefrance'
			total values of owners whose qualities are owned by the depositary 'banquedefrance'
*/
--------------------------------------------------------------------------------
CREATE VIEW ob_vowned AS SELECT 
		q.name as qname,
		o.name as owner,
		sum(s.qtt) as qtt,
		min(s.created) as created,
		max(CASE WHEN s.updated IS NULL 
			THEN s.created ELSE s.updated END) 
			as updated
    	FROM ob_tstock s 
		INNER JOIN ob_towner o ON (s.own=o.id) 
		INNER JOIN ob_tquality q on (s.np=q.id) 
	GROUP BY s.own,s.np,q.name,o.name;
GRANT SELECT ON ob_vowned TO market;

--------------------------------------------------------------------------------
-- ob_vbalance 
--------------------------------------------------------------------------------
-- PUBLIC
/* List of values owned by users GROUP BY q.name,q.own
view
	returns sum(qtt)  for each quality.
			qname:		quality.name
			qtt:		sum(qtt) for this (quality)
			created:	min(created)
			updated:	max(updated?updated:created)
	usage:
	
		SELECT * FROM ob_vbalance WHERE qown='banquedefrance'
			total values owned by the depositary 'banquedefrance'
			
		SELECT * FROM ob_vbalance WHERE qtt != 0 and qown='banquedefrance'
			Is empty if accounting is correct for the depositary
*/
--------------------------------------------------------------------------------
CREATE VIEW ob_vbalance AS SELECT 
    		q.name as qname,
		sum(s.qtt) as qtt,
    		min(s.created) as created,
    		max(CASE WHEN s.updated IS NULL 
			THEN s.created ELSE s.updated END)  
			as updated
    	FROM ob_tstock s INNER JOIN ob_tquality q on (s.np=q.id)
	GROUP BY q.name;
GRANT SELECT ON ob_vbalance TO market;

--------------------------------------------------------------------------------
-- ob_vdraft
--------------------------------------------------------------------------------
-- PUBLIC
/* List of draft by owner
view
		returns a list of drafts where the owner is partner.
			did		draft.id		
			status		'Draft','Accepted' or 'Refused'
			owner		owner providing the value
			cntcommit	number of commits
			flags		[0] set when accepted by owner
					[1] set when refuse by owner
			created:	timestamp
	usage:
		SELECT * FROM market.vdraft WHERE owner='toto'
			list of drafts for the owner 'toto'
*/
--------------------------------------------------------------------------------
CREATE VIEW ob_vdraft AS 
		SELECT 	
			dr.id as did,
			dr.status as status,
			w.name as owner,
			co.cnt as cntcommit,
			co.flags as flags,
			dr.created as created
		FROM (
			SELECT c.did,c.wid,(bit_or(c.flags)&2)|(bit_and(c.flags)&1) as flags,count(*) as cnt 
			FROM ob_tcommit c GROUP BY c.wid,c.did 
				) AS co 
		INNER JOIN ob_tdraft dr ON co.did = dr.id
		INNER JOIN ob_towner w ON w.id = co.wid;
GRANT SELECT ON ob_vdraft TO market;


--------------------------------------------------------------------------------
-- ob_vcommit
--------------------------------------------------------------------------------
CREATE VIEW ob_vcommit AS 
		SELECT 	
			co.did as draft,
			co.bid as bid,
			co.id as commit,
			sw.name as owner,
			sq.name as provides,
			ss.qtt as qtt,
			co.flags as flags
		FROM ob_tcommit co 
		INNER JOIN ob_tstock ss ON co.sid_dst = ss.id
		INNER JOIN ob_towner sw ON sw.id = ss.own
		INNER JOIN ob_tquality sq ON sq.id = ss.np;
GRANT SELECT ON ob_vcommit TO market;

--------------------------------------------------------------------------------
-- ob_vbid
--------------------------------------------------------------------------------
-- PUBLIC
/* List of bids
view
		returns a list of bids.
			id			noeud.id		
			owner			w.owner
			required_quality
			required quantity
			omega
			provided quality
			provided_quantity
			sid
			qtt
			created	
	usage:
		SELECT * FROM ob_vbid WHERE owner='toto'
			list of bids of the owner 'toto'
*/
--------------------------------------------------------------------------------
CREATE VIEW ob_vbid AS 
	SELECT 	
		n.id as id,
		w.name as owner,
		qr.name as required_quality,
		n.qtt_requ as required_quantity,
		CAST(n.qtt_prov as double precision)/CAST(n.qtt_requ as double precision) as omega,
		qp.name as provided_quality,
		n.qtt_prov as provided_quantity,
		s.id as sid,
		s.qtt as qtt,
		n.created as created
	FROM ob_tnoeud n
	INNER JOIN ob_tquality qr ON n.nr = qr.id 
	INNER JOIN ob_tstock s ON n.sid = s.id
	INNER JOIN ob_tquality qp ON s.np = qp.id
	INNER JOIN ob_towner w on s.own = w.id
	ORDER BY n.created DESC;
GRANT SELECT ON ob_vbid TO market;

--------------------------------------------------------------------------------
-- ob_vmvt R
--------------------------------------------------------------------------------
-- view PUBLIC
/* 
		returns a list of movements related to the owner.
			id		ob_tmvt.id
			did:		NULL for a movement made by ob_fadd_account()
					not NULL for a draft executed, even if it has been deleted.
			provider
			nat:		quality.name moved
			qtt:		quantity moved, 
			receiver
			created:	timestamp

*/
--------------------------------------------------------------------------------
CREATE VIEW ob_vmvt AS 
	SELECT 	m.id as id,
		m.did as did,
		w_src.name as provider,
		q.name as nat,
		m.qtt as qtt,
		w_dst.name as receiver,
		m.created as created
	FROM ob_tmvt m
	INNER JOIN ob_towner w_src ON (m.own_src=w_src.id)
	INNER JOIN ob_towner w_dst ON (m.own_dst=w_dst.id) 
	INNER JOIN ob_tquality q ON (m.nat = q.id);
	
GRANT SELECT ON ob_vmvt TO market;

--------------------------------------------------------------------------------
-- ob_fstats
--------------------------------------------------------------------------------
-- PUBLIC
/* usage:
	ret = ob_fstats()


	returns a list of ob_yret_stats
*/
--------------------------------------------------------------------------------

CREATE TYPE ob_yret_stats AS (

	mean_time_drafts int8, -- mean of delay for every drafts
	
	nb_drafts		int8,
	nb_noeuds		int8,
	nb_stocks		int8,
	nb_stocks_s	int8,
	nb_stocks_d	int8,
	nb_stocks_a	int8,
	nb_qualities 	int8,
	nb_owners		int8,
	
	-- followings should be all 0
	unbalanced_qualities 	int8,
	corrupted_draft		int8,
	corrupted_stock_s	int8,
	corrupted_stock_a	int8,
	
	created timestamp
);
-- select (unbalanced_qualities+corrupted_draft+corrupted_stock_s+corrupted_stock_a from ob_fstats();
--------------------------------------------------------------------------------
CREATE FUNCTION ob_fstats() RETURNS ob_yret_stats AS $$
DECLARE
	ret ob_yret_stats%rowtype;
	delays int8;
	cnt int8;
	err int8;
	_draft ob_tdraft%rowtype;
	res int;
	_user text;
	_x int;
BEGIN
	_x := ob_fcan_exec();
	ret.created := statement_timestamp();
	
	-- mean time of draft
	SELECT SUM(delay),count(*) INTO delays,cnt FROM ob_tdraft;
	ret.nb_drafts := cnt;
	ret.mean_time_drafts = CAST( delays/cnt AS INT8);
	
	SELECT count(*) INTO cnt FROM ob_tnoeud;
	ret.nb_noeuds := cnt;
	SELECT count(*) INTO cnt FROM ob_tstock;
	ret.nb_stocks := cnt;
	SELECT count(*) INTO cnt FROM ob_tstock WHERE type='Account';
	ret.nb_stocks_a := cnt;
	SELECT count(*) INTO cnt FROM ob_tstock WHERE type='Draft';
	ret.nb_stocks_d := cnt;
	SELECT count(*) INTO cnt FROM ob_tstock WHERE type='Stock';
	ret.nb_stocks_s := cnt;
	SELECT count(*) INTO cnt FROM ob_tquality;
	ret.nb_qualities := cnt;
	SELECT count(*) INTO cnt FROM ob_towner;
	ret.nb_owners := cnt;	

	-- number of unbalanced qualities 
	-- for a given quality, we should have:
	-- 	sum(stock_A.qtt)+sum(stock_S.qtt)+sum(stock_D.qtt) = quality.qtt 
	SELECT count(*) INTO cnt FROM (
		SELECT sum(abs(s.qtt)) 
		FROM ob_tstock s,ob_tquality q WHERE s.np=q.id
		GROUP BY s.np,q.qtt having (sum(abs(s.qtt))!= q.qtt)
	) as q;
	ret.unbalanced_qualities := cnt;
	
	-- number of draft corrupted
	ret.corrupted_draft := 0;
	ret.nb_drafts := 0;
	FOR _draft IN SELECT * FROM ob_tdraft LOOP
		res := ob_fread_status_draft(_draft);
		IF(res < 0) THEN 
			ret.corrupted_draft := ret.corrupted_draft +1;
		ELSE  
			ret.nb_drafts := ret.nb_drafts +1;
		END IF;
	END LOOP;
	
	-- stock corrupted
	-- stock_s unrelated to a bid should not exist 
	SELECT count(s.id) INTO err FROM ob_tstock s 
		LEFT JOIN ob_tnoeud n ON n.sid=s.id
	WHERE s.type='Stock' AND n.id is NULL;
	ret.corrupted_stock_s := err;
	-- Stock_A not unique
	SELECT count(*) INTO err FROM(
		SELECT count(s.id) FROM ob_tstock s 
		WHERE s.type='Account'
		GROUP BY s.np,s.own HAVING count(s.id)>1) as c;
	ret.corrupted_stock_a := err;
	RETURN ret;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION ob_fstats() TO market;
CREATE FUNCTION ob_fget_errs() RETURNS bigint AS $$
select (unbalanced_qualities+corrupted_draft+corrupted_stock_s+corrupted_stock_a) AS result from ob_fstats();
$$ LANGUAGE SQL;

--------------------------------------------------------------------------------
-- ob_fadd_account 
-- PUBLIC
/* usage:
	ret int = ob_fadd_account(owner text,quality text,_qtt int8)
	
	conditions:
		quality  exist,
		_qtt >=0
		
	actions:
		owner is created if it does not exist
		moves qtt from 	market_account[nat]		->	owners_account[own,nat]
		accounts are created when they do not exist
		the movement is recorded.
			
	returns 0 when done correctly
*/
--------------------------------------------------------------------------------
CREATE FUNCTION 
	ob_fadd_account(_owner text,_quality text,_qtt int8) 
	RETURNS int AS $$
DECLARE
	_wid int8;
	_q  ob_tquality%rowtype;
	_id_mvt int8;
	_x int;
BEGIN
	_x := ob_fcan_exec();
	_q := ob_fupdate_quality(_quality,_qtt,true);
	
	BEGIN
		INSERT INTO ob_towner (name) VALUES ( _owner) 
			RETURNING id INTO _wid;
	EXCEPTION WHEN unique_violation THEN 
	END;
	SELECT id INTO _wid from ob_towner WHERE name=_owner;
	_id_mvt := ob_fadd_to_account(1,_wid,_qtt,_q.id);
	RETURN 0;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION ob_fadd_account(text,text,int8) TO market;

	
--------------------------------------------------------------------------------
-- ob_fsub_account R
-- PUBLIC
/* usage:
	ret int = ob_fsub_account(_owner text,_quality text,_qtt int8)
	
	conditions:
		owner and quality  exist,
		_qtt >=0
		
	actions:
		moves qtt from 	
			market_account[nat]	<-owners_account[own,nat]
		account are deleted when empty
		the movement is recorded.
			
	returns 0 when done correctly
*/
--------------------------------------------------------------------------------
CREATE FUNCTION 
	ob_fsub_account(_owner text,_quality text,_qtt int8) 
	RETURNS int AS $$
DECLARE
	_wid int8;
	_np int8;
	_qtt_quality int8;
	acc ob_tstock%rowtype;
	mar ob_tstock%rowtype;
	mvt ob_tmvt%rowtype;
	_q ob_tquality%rowtype;
	_x int;
BEGIN
	_x := ob_fcan_exec();
	SELECT s.* INTO acc FROM ob_tstock s,ob_tquality q,ob_towner w
		WHERE q.name=_quality 
		AND w.name= _owner 
		AND s.own=w.id AND s.np=q.id AND  s.type='Account'  AND s.qtt >= _qtt
		LIMIT 1 FOR UPDATE OF s,q;
	IF NOT FOUND THEN
		RAISE NOTICE '[-30404] the account is empty or not big enough';
		RETURN -30404;
	END IF;
	
	IF(acc.qtt = _qtt) THEN
		DELETE FROM ob_tstock WHERE id = acc.id;
	ELSE
		UPDATE ob_tstock SET qtt = qtt - _qtt 
			WHERE id = acc.id RETURNING * INTO acc;
	END IF;
	
	_q := ob_fupdate_quality(_quality,_qtt,false);
	
	INSERT INTO ob_tmvt (own_src,own_dst,qtt,nat) 
		VALUES (acc.own,1,_qtt,acc.np) RETURNING * 
		INTO mvt;

	RETURN 0;
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION ob_fsub_account(text,text,int8) TO market;

--------------------------------------------------------------------------------
CREATE FUNCTION 
	ob_fupdate_quality(_quality_name text,_qtt int8,positive bool) 
	RETURNS ob_tquality AS $$
DECLARE 
	_q ob_tquality%rowtype;
	_np int8;
	_qtt_quality int8;
BEGIN
	SELECT id,qtt INTO _np,_qtt_quality FROM ob_tquality 
		WHERE name =  _quality_name FOR UPDATE;
	IF NOT FOUND THEN 
		INSERT INTO ob_tquality (name,qtt) VALUES ( _quality_name,0) 
			RETURNING id,qtt INTO _np,_qtt_quality;
	END IF;
	IF(positive) THEN
		UPDATE ob_tquality SET qtt = qtt + _qtt 
			WHERE id= _np RETURNING * INTO _q;
	
		IF (_qtt_quality > _q.qtt ) THEN 
			RAISE EXCEPTION '[-30433] Quality % owerflows',_quality   USING ERRCODE='38000';
		END IF;
	ELSE
		UPDATE ob_tquality SET qtt = qtt - _qtt 
			WHERE id= _np RETURNING * INTO _q;
	
		IF (_qtt_quality < _q.qtt ) THEN 
			RAISE EXCEPTION '[-30434] Quality % underflows',_quality   USING ERRCODE='38000';
		END IF;
	END IF;	
	RETURN _q;
END;
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
-- ob_fread_status_draft
--------------------------------------------------------------------------------
-- PRIVATE  used by ob_faccept_draft,ob_frefuse_draft,ob_fstats
/* usage: 
	ret int = ob_fread_status_draft(draft ob_tdraft)
	
conditions:
	draft_id exists
	the status of draft is normal
	
returns:
	verify the status of draft
	0	no error
	-30418,-30419	error

*/
--------------------------------------------------------------------------------

CREATE 
	FUNCTION ob_fread_status_draft(draft ob_tdraft) 
	RETURNS int AS $$
DECLARE
	_commot		ob_tcommit%rowtype;
	cnt		int := 0;
	_andflags	int4 := ~0;
	_orflags	int4 := 0;
	expected	ob_ydraft;
BEGIN	-- 
	SELECT bit_and(flags),bit_or(flags),count(id) 
		INTO _andflags,_orflags,cnt FROM ob_tcommit 
		WHERE did = draft.id;
	IF(cnt <2) THEN
		RETURN -30418;
	END IF;
	expected := 'Draft';
	IF(_orflags & 2 = 2) THEN -- one _commot.flags[1] set 
		expected := 'Refused';
	ELSE
		IF(_andflags & 1 = 1) THEN -- all _commot.flags[0] set
			expected :='Accepted';
		END IF;
	END IF;
	IF(draft.status != expected) THEN
		RETURN -30419;
	END IF;
	RETURN 0;
END;
$$ LANGUAGE PLPGSQL;

--------------------------------------------------------------------------------
CREATE FUNCTION 
	ob_fupdate_status_commits(draft_id int8,own_id int8,_flags int4,mask int4) 
	RETURNS int AS $$
DECLARE 
	cnt		int := 0;
BEGIN
	SELECT count(c.id) INTO cnt FROM ob_tcommit c
	WHERE c.did=draft_id  AND c.wid = own_id;
	IF cnt = 0 THEN
		RAISE EXCEPTION '[-30416] No stock of the draft % is owned by %',draft_id,own_id;
	END IF; 
	UPDATE ob_tcommit 
	SET flags = (_flags & mask) |(flags & (~mask)) 
	WHERE  did = draft_id AND wid = own_id;	
	RETURN cnt;
END;
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
-- test on return is NULL
CREATE FUNCTION 
	ob_acquires_locks_draft(draft_id int8) 
	RETURNS ob_tdraft AS $$
DECLARE 
	draft		ob_tdraft%rowtype;
BEGIN
	SELECT d.* INTO draft FROM ob_tdraft d,ob_tcommit c,ob_tstock s
		WHERE d.id = draft_id AND c.did=d.id
		AND (s.id = c.sid_src OR s.id = c.sid_dst ) FOR UPDATE;
	RETURN draft;
END;
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
-- test on return is NULL
CREATE FUNCTION 
	ob_is_partner_draft(draft_id int8,name_owner text) 
	RETURNS ob_towner AS $$
DECLARE 
	owner		ob_towner%rowtype;
BEGIN
	SELECT o.* INTO owner FROM ob_towner o,ob_tcommit c
		WHERE o.name=name_owner AND c.wid=o.id AND c.did=draft_id;
	RETURN owner;
END;
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
CREATE FUNCTION 
	ob_fdelete_draft(draft_id int8) 
	RETURNS int AS $$
DECLARE 
	_commot		ob_tcommit%rowtype;
	_stocksSrc	int8[];
	_stocksDst	int8[];
BEGIN
		
	-- the draft is now empty, it can be deleted
	_stocksDst := ARRAY[]::int8[];
	_stocksSrc := ARRAY[]::int8[];
	FOR _commot IN SELECT * FROM ob_tcommit WHERE did = draft_id LOOP
		_stocksDst := _stocksDst || _commot.sid_dst;
		_stocksSrc := _stocksSrc || _commot.sid_src;
	END LOOP;
	DELETE FROM ob_tdraft d WHERE d.id = draft_id;
	-- commits deleted by cascade
	
	-- delete stock[sid_src] where qtt=0 and related noeud
	DELETE FROM ob_tstock s WHERE s.id = ANY (_stocksDst);
	DELETE FROM ONLY ob_tnoeud n USING ob_tstock s WHERE s.id=n.sid
		AND s.id = ANY (_stocksSrc) AND s.qtt = 0;
	DELETE FROM ob_tstock s WHERE s.id = ANY (_stocksSrc) AND s.qtt = 0;
	
	return 1;
END;
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
-- ob_faccept_draft
--------------------------------------------------------------------------------
-- PUBLIC 
/* usage: 
	ret int = ob_faccept_draft(draft_id int8,owner text)
		own_id
		draft_id
conditions:
	draft_id exists with status D

returns a char:
		0 the draft is not yet accepted, 
		1 the draft is executed, NON, retourne 0!
		< 0 error
*/
--------------------------------------------------------------------------------
CREATE FUNCTION 
	ob_faccept_draft(draft_id int8,name_owner text) 
	RETURNS int AS $$
DECLARE
	_draft 		ob_tdraft%rowtype;
	_owner		ob_towner%rowtype;
	_commot		ob_tcommit%rowtype;
	_accepted	int4; 
	_res 		int;
	_x int;
BEGIN
	_x := ob_fcan_exec();
	_draft := ob_acquires_locks_draft(draft_id);
	IF(_draft IS NULL) THEN
		RAISE NOTICE '[-30422] The draft % has not the status Draft or does not exist',draft_id;
		RETURN -30422;
	END IF;
	IF(NOT(_draft.status = 'Draft') ) THEN 
		RAISE NOTICE '[-30422] The draft % has not the status Draft or does not exist',draft_id;
		RETURN -30422;
	END IF;	
	_owner := ob_is_partner_draft(draft_id,name_owner);
	if(_owner IS NULL) THEN
		RAISE NOTICE '[-30421] The owner % does not exist or is not the partner of the draft %',name_owner,draft_id;
		RETURN -30421;
	END IF;
	
	------------- update status of commits --------------------------------	
	_res := ob_fupdate_status_commits(draft_id,_owner.id,1,3);
	
	SELECT bit_and(flags&1),count(*) INTO _accepted
		FROM ob_tcommit WHERE did = draft_id;

	------------- execute -------------------------------------------------
	if(_accepted = 1) THEN
		_res := ob_fexecute_draft(draft_id);		
		_res := ob_fdelete_draft(draft_id);
		RETURN 1;
	ELSE
		RETURN 0;
	END IF;
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION ob_faccept_draft(int8,text) TO market;

--------------------------------------------------------------------------------
-- ob_fexecute_draft
--------------------------------------------------------------------------------
-- PRIVATE called by market.faccept_draft() when the draft should be executed 
/* usage: 
	cnt_commit integer = ob_fexecute_draft(draft_id int8)
action:
	execute ob_fexecute_commit(commit_src,commit_dst) for successive commits
	
list of mvts is stored in order than an other transaction can insert movements
 at the same time
*/
--------------------------------------------------------------------------------
CREATE 
	FUNCTION ob_fexecute_draft(draft_id int8) 
	RETURNS int AS $$
DECLARE
	prev_commit	ob_tcommit%rowtype;
	first_commit	ob_tcommit%rowtype;
	_commot		ob_tcommit%rowtype;
	cnt		int;
	_mvt_id		int8;
	_mvts		int8[] := ARRAY[]::int8[];
BEGIN
	cnt := 0;
	FOR _commot IN SELECT * FROM ob_tcommit 
		WHERE did = draft_id  ORDER BY id ASC LOOP
		IF (cnt = 0) THEN
			first_commit := _commot;
		ELSE
			_mvt_id := ob_fexecute_commit(prev_commit,_commot);
			_mvts := _mvts || _mvt_id;
		END IF;
		prev_commit := _commot;
		cnt := cnt+1;
	END LOOP;
	IF( cnt < 2 ) THEN
		RAISE EXCEPTION '[-30431] The draft % has less than two commits',draft_id  USING ERRCODE='38000';
	END IF;
	
	_mvt_id := ob_fexecute_commit(_commot,first_commit);
	_mvts := _mvts || _mvt_id;
	-- sets did of movements to the first mvt.id
	UPDATE ob_tmvt set did=_mvts[1] WHERE id = any (_mvts);
	RETURN cnt;
END;
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
-- ob_fexecute_commit
--------------------------------------------------------------------------------
-- PRIVATE used by ob_fexecute_draft()
/* usage: 
	mvt_id int8 = ob_fexecute_commit(commit_src ob_tcommit,commitsdt ob_tcommit)
		(commit_src,commit_dst) are two successive commits of a draft
		
condition:
	commit_src.sid_dst exists
actions:
	moves commit_src.sid_dst to account[commit_dst.wid,stock[commit_src.sid_dst].np]
	records the movement
	removes the stock[commit_src.sid_dst]
	
returns:
	the id of the movement
*/
--------------------------------------------------------------------------------

CREATE FUNCTION 
	ob_fexecute_commit(commit_src ob_tcommit,commit_dst ob_tcommit) 
	RETURNS int8 AS $$
DECLARE
	m ob_tstock%rowtype;
	stock_src ob_tstock%rowtype;
	id_mvt int8;
	res int8;
BEGIN
	SELECT s.* INTO stock_src FROM ob_tstock s 
		WHERE s.id = commit_src.sid_dst and s.type='Draft';
	IF (stock_src IS NULL) THEN
		RAISE NOTICE '[-30429] for commit % the stock_src % was not found',commit_src.id,commit_src.sid_dst;  
		RETURN -30429;
	END IF;
	-- stock_src is deleted in ob_faccept_draft() by ob_fdelete_draft()
	id_mvt := ob_fadd_to_account(commit_src.wid,commit_dst.wid,stock_src.qtt,stock_src.np);	
	RETURN id_mvt;
END;
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
CREATE FUNCTION 
	ob_finsert_das(_own int8,_qtt int8,_np int8,_type ob_ystock)
	RETURNS ob_tstock AS $$
DECLARE
	_m ob_tstock%rowtype;
BEGIN
	BEGIN
		INSERT INTO ob_tstock (own,qtt,np,type) 
			VALUES (_own,_qtt,_np,_type) 
			RETURNING * INTO _m; 
	EXCEPTION WHEN exclusion_violation THEN
		-- at this point, we are shure Account(own,np) exists
		UPDATE ob_tstock SET qtt = qtt + _qtt 
			WHERE own = _own AND np = _np AND type = _type  
			RETURNING * INTO _m;
	END;
	return _m;
END;
$$LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------

CREATE FUNCTION 
	ob_fadd_to_account(w_from int8,w_to int8,_qtt int8,_np int8) 
	RETURNS int8 AS $$
DECLARE 
	id_mvt int8;
	m ob_tstock%rowtype;
BEGIN
	m := ob_finsert_das(w_to,_qtt,_np,'Account');
	
	IF(w_from != w_to) THEN
		INSERT INTO ob_tmvt (own_src,own_dst,qtt,nat) 
			VALUES (w_from,w_to,_qtt,_np) 
			RETURNING id INTO id_mvt;
	ELSE
		id_mvt := 0;
	END IF;
	RETURN id_mvt;
END;
$$ LANGUAGE PLPGSQL;
/*
CREATE 
	FUNCTION f4() 
	RETURNS int AS $$
DECLARE
	k int;
	m ob_tstock%rowtype;
BEGIN
	BEGIN
		INSERT INTO ob_tstock (own,qtt,np,type) 
			VALUES (3,3,3,'Account') 
			RETURNING * INTO m; 
	EXCEPTION WHEN exclusion_violation THEN 
		UPDATE ob_tstock SET qtt = qtt + 3 
			WHERE own = 3 AND np = 3 AND type = 'Account'  
			RETURNING * INTO m;
	END;
	RETURN k;
END;
$$ LANGUAGE PLPGSQL;
*/

--------------------------------------------------------------------------------
-- ob_frefuse_draft
--------------------------------------------------------------------------------
-- PUBLIC 
/* usage: 
	ret int = ob_frefuse_draft(draft_id int8,owner text)
		own_id
		draft_id
	quantities are stored back into the stock S
	A ret is returned.
		1 the draft is cancelled
		<0 error

*/
--------------------------------------------------------------------------------
CREATE FUNCTION 
	ob_frefuse_draft(draft_id int8,name_owner text) 
	RETURNS int AS $$
DECLARE
	_owner	 ob_towner%rowtype;
	_res	int;
	_draft ob_tdraft%rowtype;
	_x int;
BEGIN
	_x := ob_fcan_exec();
	_draft := ob_acquires_locks_draft(draft_id);
	IF(_draft IS NULL) THEN
		RAISE NOTICE '[-30422] The draft % has not the status Draft or does not exist',draft_id;
		RETURN -30422;
	END IF;
	IF(NOT(_draft.status = 'Draft') ) THEN 
		RAISE NOTICE '[-30422] The draft % has not the status Draft or does not exist',draft_id;
		RETURN -30422;
	END IF;	
	_owner := ob_is_partner_draft(draft_id,name_owner);
	if(_owner IS NULL) THEN
		RAISE NOTICE '[-30421] The owner % does not exist or is not the partner of the draft %',name_owner,draft_id;
		RETURN -30421;
	END IF;
	_res := ob_frefuse_draft_int(_owner,_draft);

	RETURN 0;
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION ob_frefuse_draft(int8,text)  TO market;
--------------------------------------------------------------------------------
CREATE FUNCTION 
	ob_frefuse_draft_int(owner ob_towner,draft ob_tdraft) 
	RETURNS int as $$
DECLARE
	_commot	ob_tcommit%rowtype;
	_res		int:= 0;
	_qtt		int8;
	stock		ob_tstock%rowtype;
	_cbid_prec	int8 := NULL;
	_cbid_first	int8;

BEGIN
	-- the status of the draft is unchanged, since it will be deleted	
	------------- refuse  --------------------------------------------------
	-- relations between bids (X->Y) are marked as refused for bids Y owned by owner
	FOR _commot IN SELECT * FROM ob_tcommit WHERE did = draft.id LOOP
		-- RAISE INFO 'commit(%,%)',_commot.wid,_commot.bid;
		IF(_cbid_prec is NULL) THEN
			IF(owner.id = _commot.wid) THEN
				_cbid_first := _commot.bid;
			END IF;
		ELSE
			IF(owner.id = _commot.wid) THEN
				-- (prec->bid) inserted
				-- RAISE INFO 'ref(%->%)',_cbid_prec,_commot.bid;
				INSERT INTO ob_trefused (x,y) VALUES (_cbid_prec,_commot.bid);
			END IF;
		END IF;
		_cbid_prec := _commot.bid;
		
		-- commit.sid_src <- commit.sid_dst
		_qtt := ob_get_qtt_commit(_commot);
		-- stock[_commot.sid_src] is increased
		UPDATE ob_tstock SET qtt = qtt+_qtt 
			WHERE id=_commot.sid_src;
		-- but stock[_commot.sid_dst] is unchanged since it will be deleted [A]
	END LOOP;
	
	IF(NOT _cbid_first is NULL) THEN
		-- (last->first) inserted 
		-- RAISE INFO 'ref2(%->%)',_commot.bid,_cbid_first;
		INSERT INTO ob_trefused (x,y) VALUES (_commot.bid,_cbid_first);
	END IF;
	
	------------- delete draft --------------------------------------------
	_res := ob_fdelete_draft(draft.id); -- [A]
	RETURN _res;
END;
$$ LANGUAGE PLPGSQL;	
--------------------------------------------------------------------------------
CREATE FUNCTION 
	ob_get_qtt_commit(commit ob_tcommit) 
	RETURNS int8 AS $$
DECLARE 
	_qtt int8;
BEGIN
	SELECT qtt INTO _qtt FROM ob_tstock 
		WHERE id=commit.sid_dst AND TYPE='Draft'; 
	IF (NOT FOUND) THEN 
		RAISE EXCEPTION '[-30437] stockD % of draft % not found',commit.sid_dst,commit.did;
	END IF;
	return _qtt;
END;
$$ LANGUAGE PLPGSQL;
--------------------------------------------------------------------------------
-- ob_fdelete_bid
--------------------------------------------------------------------------------
-- PUBLIC 
/* usage: 
	err int = ob_fdelete_bid(bid_id int8)
	
	delete bid and related drafts
	delete related stock if it is not related to an other bid
		(in this case, the stock is not referenced by any draft). The quantity of this stock is moved back to the account.
	
	A given stock is deleted by the market.fdelete_bid of the last bid it references.
*/
--------------------------------------------------------------------------------
CREATE FUNCTION 
	ob_fdelete_bid(bid_id int8) RETURNS int AS $$
DECLARE
	_stock		ob_tstock%rowtype;
	_cnt		int;
	_draft		ob_tdraft%rowtype;
	_own		ob_towner%rowtype;
	_id		int8;
	_ret		int;
	_x 		int;
BEGIN
	_x := ob_fcan_exec();
	SELECT s.* INTO _stock FROM ob_tstock s,ob_tnoeud n
		WHERE s.id=n.sid AND n.id=bid_id 
		FOR UPDATE;
	IF NOT FOUND THEN 
		RAISE EXCEPTION '[-30413] The bid % does not exist',bid_id;
	END IF;
	SELECT * INTO _own FROM ob_towner where _stock.own=id;
	------------------------------------------------------------------------
	FOR _draft IN SELECT d.* FROM ob_tdraft d 
		WHERE d.status='Draft' AND d.id = ANY (
			SELECT c.did FROM ob_tcommit c
				WHERE c.bid = bid_id
		) FOR UPDATE LOOP
		
		_ret := ob_frefuse_draft_int(_own,_draft);
		-- RAISE INFO 'ici %', ob_fget_errs();		
	END LOOP;
	
	-- _stock is changed
	SELECT * INTO _stock FROM ob_tstock WHERE id = _stock.id;
	-- no draft reference this bid
	DELETE FROM ob_tnoeud WHERE id=bid_id; -- casade on ob_trefused
	-- the stock S is deleted if no other bid reference it.
	SELECT count(id) INTO _cnt FROM ob_tnoeud 
		WHERE sid= _stock.id;
	if(_cnt =0) THEN 
		_id := ob_fadd_to_account(_stock.own,_stock.own,_stock.qtt,_stock.np);
		DELETE FROM ob_tstock WHERE id = _stock.id;
		-- the stock is removed and qtt goes back to the account
	END IF;
	RETURN 0;
END;
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION ob_fdelete_bid(int8)  TO market;

--------------------------------------------------------------------------------
-- ob_finsert_sbid
--------------------------------------------------------------------------------
-- PUBLIC
/* usage: 
	nb_draft int = ob_finsert_sbid(bid_id int8,_qttprovided int8,_qttrequired int8,_qualityrequired text)
	
	conditions:
		noeud.id=bid_id exists
		the pivot noeud.sid exists.
		_omega > 0
		_qualityrequired text
		
	action:
		inserts a bid with the same stock as bid_id. 
	
	returns nb_draft:
		the number of draft inserted.
		-30403, the bid_id was not found
		-30404, the quality of stock offered is not owned by user 
		or error returned by ob_finsert_bid_int
*/
--------------------------------------------------------------------------------		
CREATE FUNCTION 
	ob_finsert_sbid(bid_id int8,_qttprovided int8,_qttrequired int8,_qualityrequired text) 
	RETURNS int AS $$
DECLARE
	noeud	ob_tnoeud%rowtype;
	cnt 		int;
	stock 	ob_tstock%rowtype;
	_x 	int;
BEGIN
	_x := ob_fcan_exec();
	SELECT n.* INTO noeud FROM ob_tnoeud n 
		WHERE n.id = bid_id;
	IF NOT FOUND THEN
		RAISE EXCEPTION '[-30403] the bid % was not found',bid_id USING ERRCODE='38000';
	END IF;
	
	cnt := ob_finsert_bid_int(noeud.sid,_qttrequired,_qttprovided,_qualityrequired);
	RETURN cnt;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION ob_finsert_sbid(int8,int8,int8,text)  TO market;
	
--------------------------------------------------------------------------------
-- ob_finsert_bid
--------------------------------------------------------------------------------
-- PUBLIC
/* usage: 
	nb_draft int = ob_finsert_bid(_owner text,_qualityprovided text,qttprovided int8,_qttrequired int8,_qualityrequired text)

	conditions:
		stock.id=acc exists and stock.qtt >=qtt
		_omega != 0
		_qualityrequired exists
		
	action:
		inserts a stock and a bid.
	
	returns nb_draft:
		the number of draft inserted.
		nb_draft == -30404, the _acc was not big enough or it's quality not owner by the user
		or error returned by ob_finsert_bid_int

*/
--------------------------------------------------------------------------------
CREATE FUNCTION 
	ob_finsert_bid(_owner text,_qualityprovided text,_qttprovided int8,_qttrequired int8,_qualityrequired text) 
	RETURNS int AS $$
	
DECLARE
	cnt int;
	i	int8;
	_stock 	ob_tstock%rowtype;
	_m	ob_tstock%rowtype;
	_user text;
	_x 	int;
BEGIN
	_x := ob_fcan_exec();
	-- controls
	SELECT s.* INTO _stock FROM ob_tstock s 
		INNER JOIN ob_towner w ON (w.id=s.own ) 
		INNER JOIN ob_tquality q ON ( s.np=q.id )
		WHERE s.type='Account' and (s.qtt >=_qttprovided) AND q.name=_qualityprovided and w.name=_owner 
		FOR UPDATE OF s;
	IF NOT FOUND THEN
		RAISE EXCEPTION '[-30404] the account was not found or not big enough' USING ERRCODE='38000';
	END IF;
	
	UPDATE ob_tstock SET qtt = qtt - _qttprovided 
		WHERE own = _stock.own AND np = _stock.np AND type = 'Account'  
		RETURNING * INTO _m;
	INSERT INTO ob_tstock (own,qtt,np,type) 
			VALUES (_stock.own,_qttprovided,_stock.np,'Stock') 
			RETURNING * INTO _m; 
	-- _m := ob_finsert_das(_stock.own,_qttprovided,_stock.np,'Stock');

	-- RAISE INFO 'la % ',stock.id;
	cnt := ob_finsert_bid_int(_m.id,_qttprovided,_qttrequired,_qualityrequired);
	RETURN cnt;
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION ob_finsert_bid(text,text,int8,int8,text)  TO market;

--------------------------------------------------------------------------------
-- ob_finsert_bid_int
--------------------------------------------------------------------------------
-- PRIVATE used by ob_finsert_bid and ob_finsert_sbid
/* usage: 
	nb_draft int = ob_finsert_bid_int(_sid int8,_qttprovided int8,_qttrequired int8,_qualityrequired text)

	conditions:
		the pivot stock.id=_sid exists.
		_qttprovided and _qttrequired > 0
		_qualityrequired exists
		
	action:
		tries to insert a bid with the stock _sid.
	
	returns nb_draft:
		the number of draft inserted.
		when nb_draft == -1, the insert was aborted after 3 retry
		nb_draft == -6 the pivot was not found
		-30403 qualityrequired not found
		-30406 omega <=0
		-30407 the pivot was not found or not deposited to user
*/
--------------------------------------------------------------------------------
CREATE FUNCTION 
	ob_finsert_bid_int(_sid int8,_qttprovided int8,_qttrequired int8,_qualityrequired text) 
	RETURNS int AS $$
DECLARE
	_spivot ob_tstock%rowtype;
	_nr	int8;
	_bid	int8;
	_matrix int8[];
	_row    int8[];
	_nbcommit int;
	_draft_id int8;
	_sid_src int8;
	_sid_dst int8;
	_own    int8;
	_flowr  int8;
	_commit_id int8;
	_commits int8[]; -- commit.id of the pivot for each draft
	_new_noeud_id int8;
	_stock_src ob_tstock%rowtype;
	_time_begin timestamp;
	_time_current timestamp;
	_cnt int8 := 0;
BEGIN
	------------- controls ------------------------------------------------
	SELECT q.id INTO _nr FROM ob_tquality q 
		WHERE q.name = _qualityrequired;
	IF NOT FOUND THEN
		RAISE NOTICE '[-30405] the quality % was not found',_qualityrequired;
		RETURN -30405;
	END IF;

	SELECT s.* INTO _spivot FROM ob_tstock s 
		WHERE s.id = _sid and s.type='Stock';
	IF NOT FOUND THEN
		RAISE NOTICE '[-30407] the pivot % was not found',_sid;
		RETURN -30407;
	END IF; -- at this point, _sid !=0
	IF(_qttrequired <= 0 ) THEN
		RAISE NOTICE '[-30414] _qttrequired % should be > 0',_qttrequired;
		RETURN -30414;
	END IF;
	IF(_qttprovided <= 0 ) THEN
		RAISE NOTICE '[-30415] _qttrprovided % should be > 0',_qttprovided;
		RETURN -30415;
	END IF;
	------------------------------------------------------------------------

	_time_begin := clock_timestamp();
	-- _commits := ARRAY[]::int8[];
	/*-- RAISE INFO 'ob_getdraft_get(%,%,%,%)',pivot.id,_omega,pivot.nf,_nr; */
	FOR _matrix IN SELECT * FROM ob_get_drafts(_spivot,_nr,_qttprovided,_qttrequired) LOOP
		
		_nbcommit := array_upper(_matrix,1); 
		INSERT INTO ob_tdraft (status,nbnoeud) 
			VALUES ('Draft',_nbcommit)
			RETURNING id INTO _draft_id;
				
		-- RAISE NOTICE '_matrix=%',_matrix;
		FOREACH _row SLICE 1 IN ARRAY _matrix LOOP

			_bid	   := _row[1];
			_sid_src   := _row[5];
			_own       := _row[6];
			_flowr     := _row[9];
			
			IF(_bid = 0) THEN 
				_bid := NULL; -- or constraint error
			END IF;
			
			UPDATE ob_tstock set qtt = qtt - _flowr 
				WHERE id = _sid_src AND _flowr <= qtt 
				RETURNING id INTO _stock_src;
			IF(NOT FOUND) THEN
				RAISE EXCEPTION '[30408] stock[%] should exist or qtt < %',_sid_src,_flowr;
			END IF;		
			
			INSERT INTO ob_tstock (own,    np,     qtt,    type) 
				VALUES        (_own,_row[8],_flowr,'Draft') 
				RETURNING id INTO _sid_dst;

			INSERT INTO ob_tcommit(did,bid,sid_src,sid_dst,wid,flags)
				VALUES (_draft_id,_bid,  _sid_src,_sid_dst,_own,0) 
				RETURNING id INTO _commit_id;
			IF(_bid is NULL) THEN 
				_commits := _commits || _commit_id;
			END IF;
			-- 		
		END LOOP;
			
		_time_current := clock_timestamp();
		UPDATE ob_tdraft SET 
			delay = CAST(EXTRACT(microseconds FROM (_time_current - _time_begin)) AS INT8)
			WHERE id = _draft_id;
		_time_begin := _time_current;
 		_cnt := _cnt +1;
 	END LOOP;

	INSERT INTO ob_tnoeud (sid,nr,qtt_prov,qtt_requ) 
		VALUES (_spivot.id,_nr,_qttprovided,_qttrequired)
		RETURNING id INTO _new_noeud_id;
	
	IF(_cnt) THEN
		UPDATE ob_tcommit SET bid = _new_noeud_id 
			WHERE id = ANY (_commits); -- sets the noeud.id
		RETURN _cnt;
	ELSE
		RETURN 0;
	END IF;
END; 
$$ LANGUAGE PLPGSQL;


/*******************************************/
 -- GRAPH FUNCTIONS
/*******************************************/
-- id,nr,qtt_prov,qtt_requ,sid,own,qtt,np

-- read omega 		getdraft_get(0,1.0,_nr,_nf)
-- finsert_bid_int 	getdraft_get(pivot.id,_omega,pivot.nf,_nr)

create extension flow;

/*--------------------------------------------------------------------------------
read omega, returns setof array(flowr[dim-1],flowr[0])
-------------------------------------------------------------------------------*/
CREATE FUNCTION ob_get_omegas(_nr int8,_np int8) RETURNS SETOF int8[] AS $$
DECLARE 
	_FLOWNULL flow := '[]'::flow;

	_idPivot int8 := 0;
	_sidPivot int8 := 0;
	_maxDepth int;
	_x int;
BEGIN
	_x := ob_fcan_exec();
	_maxDepth := ob_create_tmp(_nr);
	
	IF (_maxDepth is NULL or _maxDepth = 0) THEN
		RETURN;
	END IF;
	-- insert the pivot
	INSERT INTO _tmp (id,sid,   nr,qtt_prov,qtt_requ,own,qtt,np, flow,     valid,depth) VALUES
			 (0 ,  0,  _nr,1,       1,       0,  1,  _np,_FLOWNULL,0,1);
	RETURN QUERY SELECT flow_get_fim1_fi(ob_fget_flows,0) FROM ob_fget_flows(_np,_maxDepth);
END; 
$$ LANGUAGE PLPGSQL SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION ob_get_omegas(int8,int8)  TO market;

/*--------------------------------------------------------------------------------
read omega, returns setof flow_to_matrix(flow)
--------------------------------------------------------------------------------*/
CREATE FUNCTION ob_get_drafts(_spivot ob_tstock,_nr int8,_qtt_prov int8,_qtt_requ int8) RETURNS SETOF int8[] AS $$
DECLARE 
	_FLOWNULL flow := '[]'::flow;
	_maxDepth int;
BEGIN
	_maxDepth := ob_create_tmp(_nr);
	
	IF (_maxDepth is NULL or _maxDepth = 0) THEN
		RETURN;
	END IF;
	-- insert the pivot
	INSERT INTO _tmp (id,      sid, nr, qtt_prov, qtt_requ,        own,        qtt,        np,     flow,valid,depth) VALUES
			 (0 ,_spivot.id,_nr,_qtt_prov,_qtt_requ,_spivot.own,_spivot.qtt,_spivot.np,_FLOWNULL,    0,    1);
	RETURN QUERY SELECT flow_to_matrix(ob_fget_flows) FROM ob_fget_flows(_spivot.np,_maxDepth);
END; 
$$ LANGUAGE PLPGSQL;

/*--------------------------------------------------------------------------------
 creates the table _tmp deleted on commit
-------------------------------------------------------------------------------*/
CREATE FUNCTION ob_create_tmp(_nr int8) RETURNS int AS $$
DECLARE 
	_obCMAXCYCLE int := ob_get_const('obCMAXCYCLE');
	_maxDepth int;
	_FLOWNULL flow := '[]'::flow;
BEGIN
	CREATE TEMP TABLE _tmp ON COMMIT DROP AS (
		WITH RECURSIVE search_backward(id,sid,nr,qtt_prov,qtt_requ,
						own,qtt,np,
						depth) AS (
			SELECT b.id, b.sid, b.nr,b.qtt_prov,b.qtt_requ,
				v.own,v.qtt,v.np,
				2
				FROM ob_tnoeud b, ob_tstock v
				WHERE 	v.np = _nr -- v->pivot
					AND b.sid = v.id 
					AND v.qtt != 0
			UNION 
			SELECT Xb.id, Xb.sid, Xb.nr,Xb.qtt_prov,Xb.qtt_requ,
				Xv.own,Xv.qtt,Xv.np,
				Y.depth + 1
				FROM ob_tnoeud Xb, ob_tstock Xv, search_backward Y
				WHERE 	Xv.np = Y.nr -- X->Y
					AND Xb.sid = Xv.id 
					AND Xv.qtt !=0 
					AND Y.depth < _obCMAXCYCLE
					AND (Xb.id,Y.id) NOT IN (SELECT x,y FROM ob_trefused)
		)
		SELECT id,sid,nr,qtt_prov,qtt_requ,own,qtt,np,_FLOWNULL as flow,0 as valid,depth FROM search_backward
	);
	SELECT max(depth) INTO _maxDepth FROM _tmp;
	RETURN _maxDepth;
END;
$$ LANGUAGE PLPGSQL;


/*--------------------------------------------------------------------------------
 returns a set of flows found in the graph contained in the table _tmp

-------------------------------------------------------------------------------*/
CREATE FUNCTION ob_fget_flows(_np int8,_maxDepth int) RETURNS SETOF flow AS $$
DECLARE 
	_cnt int;
	_cntgraph int :=0;
	_FLOWNULL flow := '[]'::flow;
	_flow flow;
	_idPivot int8 := 0;
BEGIN
	CREATE INDEX _tmp_idx ON _tmp(valid,nr);
	LOOP -- repeate as long as a draft is found
		_cntgraph := _cntgraph+1;
/*******************************************************************************
the graph is traversed forward to be reduced
*******************************************************************************/
		-- RAISE NOTICE '_maxDepth=% _np=% _idPivot=% _cntgraph=%',_maxDepth,_np,_idpivot,_cntgraph;
		WITH RECURSIVE search_forward(id,nr,np,qtt,depth) AS (
			SELECT src.id,src.nr,src.np,src.qtt,1
				FROM _tmp src
				WHERE src.id = _idPivot AND src.valid = _cntgraph-1 -- sources
					AND src.qtt != 0 
					
			UNION
			SELECT Y.id,Y.nr,Y.np,Y.qtt,X.depth + 1
				FROM search_forward X, _tmp Y
				WHERE X.np = Y.nr AND Y.valid = _cntgraph-1 -- X->Y, use of index
					AND Y.qtt != 0 
					AND Y.id != _idPivot  -- includes pivot
					-- to exclude it, it would be Y.id = _idPivot
					
					AND X.depth < _maxDepth
		) 
	
		UPDATE _tmp t 
		SET flow = CASE WHEN _np = t.nr -- source
				THEN flow_cat(_FLOWNULL,t.id,t.nr,t.qtt_prov,t.qtt_requ,t.sid,t.own,t.qtt,t.np) 
				ELSE _FLOWNULL END,
			valid = _cntgraph
		FROM search_forward sf WHERE t.id = sf.id;
		
		-- nodes that cannot be reached are deleted
		-- DELETE FROM _tmp WHERE valid != _cntgraph;
		
/*******************************************************************************
bellman_ford

At the beginning, all sources are such as source.flow=[source,]
for t in [1,_obCMAXCYCLE]:
	for all arcs[X,Y] of the graph:
		if X.flow empty continue
		flow = X.flow followed by Y
		if flow better than X.flow, then Y.flow <- flow
At the end, Each node.flow not empty is the best flow from a source to this node
with at most t traits. 
The pivot contains the best flow from a source to pivot at most _obCMAXCYCLE long

the algorithm is usually repeated for all node, but here only
_obCMAXCYCLE times. 

*******************************************************************************/	
/* il reste à prendre en compte _lastIgnore représenté pas sid==0*/

		FOR _cnt IN 1 .. _maxDepth LOOP
			UPDATE _tmp Y 
			SET flow = flow_cat(X.flow,Y.id,Y.nr,Y.qtt_prov,Y.qtt_requ,Y.sid,Y.own,Y.qtt,Y.np)
			FROM _tmp X WHERE flow_dim(X.flow) > 0 
				AND X.np  = Y.nr AND X.valid=_cntgraph AND Y.valid=_cntgraph
				AND X.id != _idPivot -- arcs pivot->sources are not considered
				AND flow_omega(Y.flow) < (flow_omegax(X.flow,Y.qtt_prov,Y.qtt_requ));
		END LOOP;
		
		-- flow of pivot
		SELECT flow INTO _flow FROM _tmp WHERE id = _idPivot; 
		EXIT WHEN flow_dim(_flow) = 0;
		
		RETURN NEXT _flow; -- new row returned
		
		
		-- values used by this flow are substracted from _tmp
		DECLARE
			_flowr int8;
			_sid   int8;
			_dim   int;
			_flowrs int8[];
			_sids   int8[];
		BEGIN
			_flowrs := flow_proj(_flow,9);
			_sids   := flow_proj(_flow,5);
			_dim    := flow_dim(_flow) - 1;
			-- RAISE NOTICE '_cntgraph=% dim=% ',_cntgraph,_dim+1;
			-- the pivot is not considered
			FOR _cnt IN 1 .. _dim LOOP
				_flowr := _flowrs[_cnt];
				_sid   := _sids[_cnt]; 
				-- RAISE NOTICE 'flowrs[%]=% ',_cnt,_flowr;
				IF(_sid != 0) THEN
					UPDATE _tmp SET qtt = qtt - _flowr WHERE sid = _sid;
				END IF;
			END LOOP;
		END;
		
		-- the flow should not produce negative values
		SELECT count(*) INTO _cnt FROM _tmp WHERE qtt < 0;
		IF (_cnt >0) THEN
			RAISE EXCEPTION '% bids was found with negative values',_cnt USING ERRCODE='38000';
		END IF;
	END LOOP;

END; 
$$ LANGUAGE PLPGSQL;
	
--------------------------------------------------------------------------------
DROP FUNCTION _reference_time(text);
DROP FUNCTION _reference_time_trig(text);
