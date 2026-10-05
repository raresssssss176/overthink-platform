-- Denumirile pot fi schimbate din panoul de administrare; ON CONFLICT evita duplicari.
INSERT INTO departments(name,slug) VALUES
 ('Tehnic','tehnic'),
 ('Actorie','actorie'),
 ('Regie și scenariu','regie-scenariu'),
 ('Estetic','estetic'),
 ('Producție și marketing','productie-marketing')
ON CONFLICT(slug) DO NOTHING;
