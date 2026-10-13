-- The ride on the back of a piece (13 October 2026): every piece names the journey that brought
-- it. A piece from a journey names that one (`journey_id`, unique: one journey, one piece). A piece
-- without one — given by the Stellwerk, or made before journeys carried pieces — names
-- `named_journey_id`: for now a random arrived journey of the same customer, so that the pieces
-- there already are show a ride too. Not unique, so two of them may name the same journey; never
-- another customer's. A deleted journey takes its name off the piece, not the piece.
--
-- Written to run twice: the API tests apply it again after making pieces without a ride.

alter table puzzle_pieces add column if not exists named_journey_id uuid references journeys(id) on delete set null;

update puzzle_pieces p
   set named_journey_id = (select j.id from journeys j
                            where j.customer_id = p.customer_id and j.status = 'arrived'
                            order by random() limit 1)
 where p.journey_id is null and p.named_journey_id is null;
