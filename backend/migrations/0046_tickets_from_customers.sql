-- #66, docs/49 §8: what existed before tickets becomes tickets.
--
--   deutschlandticket → one D-Ticket per customer, with the number from the personal data;
--   zeitkarte         → one "Monats- oder Jahreskarte" of the Verbund standard, marked unsure (nobody
--                       was asked which Verbund); and, where such a ticket was used long-distance,
--                       one Streckenzeitkarte, also unsure — that is what the old rate did;
--   einzelfahrkarte   → one single ticket per journey (or per ride, or per case without either),
--                       without a price: the 39,90 € the ledger assumed was never anyone's fare.
--
-- A single ticket made here takes the id of the journey, ride or case it stands for, so the
-- links below need no lookup table. Ids are random UUIDs; they do not meet.

-- 1. Season tickets, once per customer who had that type anywhere.
insert into tickets (id, customer_id, product, first_class, number)
select gen_random_uuid(), c.id, 'deutschlandticket', c.first_class, c.ticket_number
  from customers c
 where c.ticket = 'deutschlandticket'
    or exists (select 1 from journeys j where j.customer_id = c.id and j.ticket = 'deutschlandticket')
    or exists (select 1 from rides r where r.customer_id = c.id and r.ticket = 'deutschlandticket')
    or exists (select 1 from incidents i where i.customer_id = c.id and i.ticket = 'deutschlandticket');

insert into tickets (id, customer_id, product, product_unsure, first_class)
select gen_random_uuid(), c.id, 'zeitkarte_spnv', true, c.first_class
  from customers c
 where c.ticket = 'zeitkarte'
    or exists (select 1 from journeys j where j.customer_id = c.id and j.ticket = 'zeitkarte')
    or exists (select 1 from rides r where r.customer_id = c.id and r.ticket = 'zeitkarte')
    or exists (select 1 from incidents i where i.customer_id = c.id and i.ticket = 'zeitkarte');

insert into tickets (id, customer_id, product, product_unsure, first_class)
select gen_random_uuid(), c.id, 'streckenzeitkarte', true, c.first_class
  from customers c
 where exists (select 1 from rides r where r.customer_id = c.id and r.ticket = 'zeitkarte' and r.category = 'fern');

-- 2. Single tickets: one per journey, per ride without a journey, per case without either.
insert into tickets (id, customer_id, product, first_class, created_at)
select j.id, j.customer_id, 'einzel_db', c.first_class, j.created_at
  from journeys j join customers c on c.id = j.customer_id
 where j.ticket = 'einzelfahrkarte';

insert into tickets (id, customer_id, product, first_class, created_at)
select r.id, r.customer_id, 'einzel_db', c.first_class, r.checked_in_at
  from rides r join customers c on c.id = r.customer_id
 where r.ticket = 'einzelfahrkarte' and r.journey_id is null;

insert into tickets (id, customer_id, product, first_class, created_at)
select i.id, i.customer_id, 'einzel_db', c.first_class, i.created_at
  from incidents i join customers c on c.id = i.customer_id
 where i.ticket = 'einzelfahrkarte' and i.journey_id is null and i.ride_id is null;

-- 3. Journeys: the ticket of their type. A Zeitkarte journey with a long-distance leg rode on the
-- Streckenzeitkarte.
insert into journey_tickets (journey_id, ticket_id)
select j.id,
       case j.ticket
           when 'einzelfahrkarte' then j.id
           when 'deutschlandticket' then (select t.id from tickets t where t.customer_id = j.customer_id and t.product = 'deutschlandticket' order by t.created_at limit 1)
           else coalesce(
               case when exists (select 1 from rides r where r.journey_id = j.id and r.category = 'fern')
                    then (select t.id from tickets t where t.customer_id = j.customer_id and t.product = 'streckenzeitkarte' order by t.created_at limit 1) end,
               (select t.id from tickets t where t.customer_id = j.customer_id and t.product = 'zeitkarte_spnv' order by t.created_at limit 1))
       end
  from journeys j;

-- 4. Rides: their journey's ticket, or their own type.
update rides r set ticket_id = jt.ticket_id from journey_tickets jt where jt.journey_id = r.journey_id;
update rides r
   set ticket_id = case r.ticket
           when 'einzelfahrkarte' then r.id
           when 'deutschlandticket' then (select t.id from tickets t where t.customer_id = r.customer_id and t.product = 'deutschlandticket' order by t.created_at limit 1)
           else coalesce(
               case when r.category = 'fern' then (select t.id from tickets t where t.customer_id = r.customer_id and t.product = 'streckenzeitkarte' order by t.created_at limit 1) end,
               (select t.id from tickets t where t.customer_id = r.customer_id and t.product = 'zeitkarte_spnv' order by t.created_at limit 1))
       end
 where r.journey_id is null;

-- 5. Cases: their journey's ticket, else their ride's, else their own type. First class as the
-- customer had it, which is what the amount was computed with.
update incidents i set ticket_id = jt.ticket_id from journey_tickets jt where jt.journey_id = i.journey_id;
update incidents i set ticket_id = r.ticket_id from rides r where i.ticket_id is null and r.id = i.ride_id;
update incidents i
   set ticket_id = case i.ticket
           when 'einzelfahrkarte' then i.id
           when 'deutschlandticket' then (select t.id from tickets t where t.customer_id = i.customer_id and t.product = 'deutschlandticket' order by t.created_at limit 1)
           else coalesce(
               case when i.amount_cents in (500, 750) then (select t.id from tickets t where t.customer_id = i.customer_id and t.product = 'streckenzeitkarte' order by t.created_at limit 1) end,
               (select t.id from tickets t where t.customer_id = i.customer_id and t.product = 'zeitkarte_spnv' order by t.created_at limit 1))
       end
 where i.ticket_id is null;
update incidents i set first_class = c.first_class from customers c where c.id = i.customer_id and i.first_class is null;
