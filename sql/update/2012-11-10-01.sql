CREATE TABLE mail_templates (
    id SERIAL PRIMARY KEY NOT NULL,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    date_created TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT ('now'::TEXT)::TIMESTAMP WITH TIME ZONE,
    date_updated TIMESTAMP WITH TIME ZONE,
    date_deleted TIMESTAMP WITH TIME ZONE,
    forms_id INT NOT NULL REFERENCES forms ( id ),
    charset TEXT NOT NULL DEFAULT 'utf8',
    "from" TEXT NOT NULL,
    "to" TEXT NOT NULL,
    cc TEXT,
    bcc TEXT,
    subject TEXT NOT NULL,
    body TEXT NOT NULL
);
CREATE INDEX idx_mail_templates_is_deleted ON mail_templates ( is_deleted );
CREATE INDEX idx_mail_templates_forms_id ON mail_templates ( forms_id );
