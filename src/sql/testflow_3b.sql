-- SET search_path TO test;
truncate torder;
truncate tstack;
truncate tmvt;
truncate towner;
SELECT setval('tstack_id_seq',1,false);

copy torder from '/home/olivier/ob92/src/sql/torder_test_10000.sql';
copy towner from '/home/olivier/ob92/src/sql/towner_test_10000.sql';
truncate tstack;
SELECT setval('tstack_id_seq',10000,true);
SELECT setval('tmvt_id_seq',1,true);

select * from fsubmitquote(2,'own82','qlt22','qlt23');select * from fproducemvt();
select * from fsubmitquote(2,'own82','qlt22',67432,'qlt23',30183,0);select * from fproducemvt();
select * from fsubmitquote(2,'own82','qlt22',67432,'qlt23',30183,91809);select * from fproducemvt();
select * from fsubmitbarter(2,'own82',NULL,'qlt22',67432,'qlt23',30183,91809);select * from fproducemvt();
select id,nbt,nbc,xid,own_src,own_dst,qtt,nat from tmvt where id >4;
select sum(qtt) from tmvt where own_src='own82' and nat='qlt23' and id>4;
select sum(qtt) from tmvt where own_dst='own82' and nat='qlt22' and id>4;

/*
select * from fsubmitquote(1,'own82','qlt22','qlt10');select * from fproducemvt();
select * from fsubmitquote(1,'own82','qlt22',49252,'qlt10',2177,2176);select * from fproducemvt();
select * from fsubmitbarter(1,'own82',NULL,'qlt22',49252,'qlt10',2177,2176);select * from fproducemvt(); 
select xid,own_src,own_dst,qtt,nat from tmvt order by id desc limit 3;

select * from fsubmitquote(1,'own82','qlt2',60000,'qlt23',45276,45276);select * from fproducemvt();
select * from fsubmitbarter(1,'own82',NULL,'qlt2',60000,'qlt23',45276,45276);select * from fproducemvt();
select id,nbt,nbc,xid,own_src,own_dst,qtt,nat from tmvt order by id desc limit 12;
select sum(qtt) from tmvt where own_src='own82' and nat='qlt23' and id>18;
select sum(qtt) from tmvt where own_dst='own82' and nat='qlt2' and id>18;

select * from fsubmitquote(1,'own1','qlt1','qlt2');select * from fproducemvt();
select * from fsubmitquote(1,'own1','qlt1',30822,'qlt2',9667,0);select * from fproducemvt();
select * from fsubmitquote(1,'own1','qlt1',30822,'qlt2',9667,7563);select * from fproducemvt();
select * from fsubmitbarter(1,'own1',NULL,'qlt1',30822,'qlt2',9667,7563);select * from fproducemvt();
select id,nbt,nbc,xid,own_src,own_dst,qtt,nat from tmvt d where id>33;
select sum(qtt) from tmvt where own_src='own1' and nat='qlt2' and id>33;
select sum(qtt) from tmvt where own_dst='own1' and nat='qlt1' and id>33;
*/


