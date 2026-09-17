-- A desk is written to at one address and answers from another: mail to the Servicecenter's inbox
-- at deutschebahn.com comes back from deutschebahn.de. The answer domains therefore add to the
-- domain a route's mail goes to instead of replacing it, and are managed on their own with
-- `stellwerk route answers` rather than rewritten with every `route set`.
comment on column mail_routes.reply_from is 'extra answer domains, comma-separated, besides the domain of to_address; only verified mail from these can accept, refuse or ask a claim';
