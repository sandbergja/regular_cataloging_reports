#!/bin/bash

dbname="myDB" #change this to appropriate value
hostname="myHOST" #change this to appropriate value
username="mySELF" #change this to appropriate value
email="myEmail@myDomain" #change this to appropriate value; you can separate multiple email addresses with commas
this_month=`date +%m`
log_file="cataloging_reports.tmp"

psql $dbname -h $hostname -U $username << EOF
\o cataloging_reports.tmp
---monthly: report of items missing 245
SELECT  DISTINCT b.id as tcn, ou.name as library, cn.label as call_number, c.barcode, 'Missing 245 (title) field' as issue
  FROM biblio.record_entry b
  INNER JOIN asset.call_number cn ON cn.record=b.id
  INNER JOIN asset.copy c ON c.call_number=cn.id
  INNER JOIN actor.org_unit ou on ou.id=c.circ_lib
  WHERE b.deleted=FALSE
  AND b.marc NOT LIKE '%tag="245%'
  AND b.id != -1
  ORDER BY library;


---monthly: report of very small items
SELECT  DISTINCT b.id as tcn, ou.name as library, cn.label as call_number, c.barcode, xpath('//m:datafield[@tag="245"]/m:subfield[@code="a"]/text()', b.marc::xml, ARRAY[ARRAY['m','http://www.loc.gov/MARC21/slim']])::VARCHAR as title, CONCAT('only ', ((char_length(b.marc)-char_length(replace(b.marc, '/datafield', '')))/10), ' fields in record') as issue
  FROM biblio.record_entry b
  INNER JOIN asset.call_number cn ON cn.record=b.id
  INNER JOIN asset.copy c ON c.call_number=cn.id
  INNER JOIN actor.org_unit ou on ou.id=c.circ_lib
  WHERE b.deleted=FALSE
  AND ((char_length(b.marc)-char_length(replace(b.marc, '/datafield', '')))<(10*7))
  AND b.id != -1
  AND c.location !=238 -- LBCC ILL
  AND c.location !=171 -- Main's FIX
  AND c.location !=177 -- Carnegie's FIX
  AND c.location !=192 -- Lebanon's FIX
  AND c.location !=237 -- LBCC's Servc-Desk
  AND c.location !=229 -- LBCC's Reserves
  AND c.location !=203 -- APL's On Order
  AND c.location !=210 -- APL's On Order
  AND c.location !=183 -- APL's Reserves
  AND cn.label NOT LIKE 'ILL%'
  ORDER BY library;

---monthly: items missing circmods
SELECT ou.name as library, b.id as tcn, cn.label as call_number, c.circ_modifier, c.barcode, xpath('//m:datafield[@tag="245"]/m:subfield[@code="a"]/text()', b.marc::xml, ARRAY[ARRAY['m','http://www.loc.gov/MARC21/slim']]) as title, 'Missing circ mod' as issue
  FROM biblio.record_entry b
  INNER JOIN asset.call_number cn ON cn.record=b.id
  INNER JOIN asset.copy c ON c.call_number=cn.id
  INNER JOIN actor.org_unit ou on ou.id=c.circ_lib
  WHERE b.deleted=FALSE
  AND c.deleted=FALSE
  AND b.id != -1
  AND c.circ_modifier IS NULL
  ORDER BY library;

---monthly: items in "undefined" copy location
SELECT ou.name as library, b.id as tcn, cn.label as call_number, c.barcode, xpath('//m:datafield[@tag="245"]/m:subfield[@code="a"]/text()', b.marc::xml, ARRAY[ARRAY['m','http://www.loc.gov/MARC21/slim']]) as title, 'Undefined copy location' as issue
  FROM biblio.record_entry b
  INNER JOIN asset.call_number cn ON cn.record=b.id
  INNER JOIN asset.copy c ON c.call_number=cn.id
  INNER JOIN actor.org_unit ou on ou.id=c.circ_lib
  WHERE b.deleted=FALSE
  AND c.deleted=FALSE
  AND b.id != -1
  AND c.location = 1
  ORDER BY library;

---monthly: new local authority records
SELECT value AS new_authority_headings
  FROM authority.simple_heading, authority.control_set_authority_field, authority.record_entry
  WHERE thesaurus = 'L' -- local authorities
  AND simple_heading.atag=control_set_authority_field.id
  AND simple_heading.record = record_entry.id
  AND tag LIKE '1%' -- only authoritized headings
  AND create_date > (current_date - interval '1 month'); -- just in the past month

---monthly: empty volumes that are the last volume attached to a bib record
 SELECT org_unit.name AS library, record AS tcn, 'Has an empty volume' AS issue
  FROM asset.call_number, actor.org_unit
  WHERE NOT deleted AND edit_date<(now() - interval '2 months')
  AND call_number.id NOT IN (SELECT call_number FROM asset.copy WHERE NOT deleted)
  AND record IN (SELECT record FROM asset.call_number WHERE NOT deleted GROUP BY record HAVING COUNT(*) < 2)
  AND owning_lib=org_unit.id AND ou_type=3
  ORDER BY library, tcn;

\o
EOF

cat $log_file | mail -s "Monthly cataloging reports" $email

if test $(($this_month%2)) -eq 0; then
psql $dbname -h $hostname -U $username << EOF
\o cataloging_reports.tmp

---every other month: report of items missing 260/264
SELECT DISTINCT b.id as tcn, ou.name as library, cn.label as call_number, c.barcode, xpath('//m:datafield[@tag="245"]/m:subfield[@code="a"]/text()', b.marc::xml, ARRAY[ARRAY['m','http://www.loc.gov/MARC21/slim']])::VARCHAR as title, 'Missing 260 and 264 fields (publication info)' as issue
  FROM biblio.record_entry b
  INNER JOIN asset.call_number cn ON cn.record=b.id
  INNER JOIN asset.copy c ON c.call_number=cn.id
  INNER JOIN actor.org_unit ou on ou.id=c.circ_lib
  WHERE b.deleted=FALSE
  AND b.marc NOT LIKE '%tag="260%'
  AND b.marc NOT LIKE '%tag="264%'
  AND c.location !=238 -- LBCC ILL
  AND c.location !=171 -- Main's FIX
  AND c.location !=177 -- Carnegie's FIX
  AND c.location !=192 -- Lebanon's FIX
  AND c.location !=237 -- LBCC's Servc-Desk
  AND c.location !=229 -- LBCC's Reserves
  AND c.location !=203 -- APL's On Order
  AND c.location !=210 -- APL's On Order
  AND c.location !=183 -- APL's Reserves
  AND cn.label NOT LIKE 'ILL%'
  AND b.id != -1
  ORDER BY library;


---every other month: report of items missing subject headings
---this was getting overwhelming, so deliver a count and a small subset to work on instead
/*
SELECT DISTINCT b.id as tcn, ou.name as library, cn.label as call_number, c.barcode, xpath('//m:datafield[@tag="245"]/m:subfield[@code="a"]/text()', b.marc::xml, ARRAY[ARRAY['m','http://www.loc.gov/MARC21/slim']])::VARCHAR as title, 'No authorized subject headings' as issue
  FROM biblio.record_entry b
  INNER JOIN asset.call_number cn ON cn.record=b.id
  INNER JOIN asset.copy c ON c.call_number=cn.id
  INNER JOIN actor.org_unit ou on ou.id=c.circ_lib
  WHERE b.deleted=FALSE
  AND b.marc NOT LIKE '%tag="600%'
  AND b.marc NOT LIKE '%tag="610%'
  AND b.marc NOT LIKE '%tag="611%'
  AND b.marc NOT LIKE '%tag="630%'
  AND b.marc NOT LIKE '%tag="650%'
  AND b.marc NOT LIKE '%tag="651%'
  AND c.location !=238 -- LBCC ILL
  AND c.location !=171 -- Main's FIX
  AND c.location !=177 -- Carnegie's FIX
  AND c.location !=192 -- Lebanon's FIX
  AND c.location !=237 -- LBCC's Servc-Desk
  AND c.location !=229 -- LBCC's Reserves
  AND c.location !=203 -- APL's On Order
  AND c.location !=210 -- APL's On Order
  AND c.location !=183 -- APL's Reserves
  AND cn.label NOT LIKE 'ILL%'
  AND b.id != -1
  ORDER BY library;
  */
  SELECT COUNT( DISTINCT b.id) AS number_of_records_without_subject_headings
  FROM biblio.record_entry b
  INNER JOIN asset.call_number cn ON cn.record=b.id
  INNER JOIN asset.copy c ON c.call_number=cn.id
  INNER JOIN actor.org_unit ou on ou.id=c.circ_lib
  WHERE b.deleted=FALSE
  AND b.marc NOT LIKE '%tag="600%'
  AND b.marc NOT LIKE '%tag="610%'
  AND b.marc NOT LIKE '%tag="611%'
  AND b.marc NOT LIKE '%tag="630%'
  AND b.marc NOT LIKE '%tag="650%'
  AND b.marc NOT LIKE '%tag="651%'
  AND c.location !=238 -- LBCC ILL
  AND c.location !=171 -- Main's FIX
  AND c.location !=177 -- Carnegie's FIX
  AND c.location !=192 -- Lebanon's FIX
  AND c.location !=237 -- LBCC's Servc-Desk
  AND c.location !=229 -- LBCC's Reserves
  AND c.location !=203 -- APL's On Order
  AND c.location !=210 -- APL's On Order
  AND c.location !=183 -- APL's Reserves
  AND cn.label NOT LIKE 'ILL%'
  AND b.id != -1;

  SELECT DISTINCT b.id as tcn, ou.name as library, cn.label as call_number, c.barcode, xpath('//m:datafield[@tag="245"]/m:subfield[@code="a"]/text()', b.marc::xml, ARRAY[ARRAY['m','http://www.loc.gov/MARC21/slim']])::VARCHAR as title, 'No authorized subject headings' as issue
  FROM biblio.record_entry b
  INNER JOIN asset.call_number cn ON cn.record=b.id
  INNER JOIN asset.copy c ON c.call_number=cn.id
  INNER JOIN actor.org_unit ou on ou.id=c.circ_lib
  WHERE b.deleted=FALSE
  AND b.marc NOT LIKE '%tag="600%'
  AND b.marc NOT LIKE '%tag="610%'
  AND b.marc NOT LIKE '%tag="611%'
  AND b.marc NOT LIKE '%tag="630%'
  AND b.marc NOT LIKE '%tag="650%'
  AND b.marc NOT LIKE '%tag="651%'
  AND c.location !=238 -- LBCC ILL
  AND c.location !=171 -- Main's FIX
  AND c.location !=177 -- Carnegie's FIX
  AND c.location !=192 -- Lebanon's FIX
  AND c.location !=237 -- LBCC's Servc-Desk
  AND c.location !=229 -- LBCC's Reserves
  AND c.location !=203 -- APL's On Order
  AND c.location !=210 -- APL's On Order
  AND c.location !=183 -- APL's Reserves
  AND cn.label NOT LIKE 'ILL%'
  AND b.id != -1 AND (c.circ_lib = 7 OR c.circ_lib=4 OR c.circ_lib=5)
  ORDER BY tcn DESC LIMIT 40;
  
  \o
EOF

cat $log_file | mail -s "Bimonthly cataloging reports" $email
fi

if test $(($this_month%3)) -eq 0; then
psql $dbname -h $hostname -U $username << EOF
\o cataloging_reports.tmp
---every three months: report of items missing 300
SELECT DISTINCT b.id as tcn, ou.name as library, cn.label as call_number, c.barcode, xpath('//m:datafield[@tag="245"]/m:subfield[@code="a"]/text()', b.marc::xml, ARRAY[ARRAY['m','http://www.loc.gov/MARC21/slim']])::VARCHAR as title, 'Missing 300 (physical description) field' as issue
  FROM biblio.record_entry b
  INNER JOIN asset.call_number cn ON cn.record=b.id
  INNER JOIN asset.copy c ON c.call_number=cn.id
  INNER JOIN actor.org_unit ou on ou.id=c.circ_lib
  WHERE b.deleted=FALSE
  AND b.marc NOT LIKE '%tag="260%'
  AND b.marc NOT LIKE '%tag="264%'
  AND b.id != -1
  AND c.location !=238 -- LBCC ILL
  AND c.location !=171 -- Main's FIX
  AND c.location !=177 -- Carnegie's FIX
  AND c.location !=192 -- Lebanon's FIX
  AND c.location !=237 -- LBCC's Servc-Desk
  AND c.location !=229 -- LBCC's Reserves
  AND c.location !=203 -- APL's On Order
  AND c.location !=210 -- APL's On Order
  AND c.location !=183 -- APL's Reserves
  AND cn.label NOT LIKE 'ILL%'
  ORDER BY library;
  \o
EOF

cat $log_file | mail -s "Quarterly cataloging reports" $email
fi
rm $log_file
