CREATE TABLE system_settings (
    id SERIAL NOT NULL PRIMARY KEY,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    date_created TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT ('now'::TEXT)::TIMESTAMP WITH TIME ZONE,
    date_updated TIMESTAMP WITH TIME ZONE,
    date_deleted TIMESTAMP WITH TIME ZONE,
    name TEXT NOT NULL,
    data TEXT
);
CREATE INDEX idx_system_settings_is_deleted ON system_settings ( is_deleted );
CREATE INDEX idx_system_settings_name ON system_settings ( name );

CREATE TABLE forms (
    id SERIAL PRIMARY KEY NOT NULL,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    date_created TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT ('now'::TEXT)::TIMESTAMP WITH TIME ZONE,
    date_updated TIMESTAMP WITH TIME ZONE,
    date_deleted TIMESTAMP WITH TIME ZONE,
    key TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    is_published BOOLEAN DEFAULT FALSE,
    date_published TIMESTAMP WITH TIME ZONE
);
CREATE INDEX forms_is_deleted ON forms ( is_deleted );

CREATE TABLE fields (
    id SERIAL PRIMARY KEY NOT NULL,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    date_created TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT ('now'::TEXT)::TIMESTAMP WITH TIME ZONE,
    date_updated TIMESTAMP WITH TIME ZONE,
    date_deleted TIMESTAMP WITH TIME ZONE,
    is_global BOOLEAN NOT NULL DEFAULT TRUE,
    name TEXT NOT NULL,
    type TEXT NOT NULL,
    "default" TEXT,
    is_required BOOLEAN NOT NULL DEFAULT FALSE,
    error_check TEXT,
    sortorder INT
);
CREATE INDEX idx_fields_is_deleted ON fields ( is_deleted );
CREATE INDEX idx_fields_sortorder ON fields ( sortorder );

CREATE TABLE form_fields (
    id SERIAL PRIMARY KEY NOT NULL,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    date_created TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT ('now'::TEXT)::TIMESTAMP WITH TIME ZONE,
    date_updated TIMESTAMP WITH TIME ZONE,
    date_deleted TIMESTAMP WITH TIME ZONE,
    forms_id INT NOT NULL REFERENCES forms ( id ),
    fields_id INT NOT NULL REFERENCES fields ( id ),
    sortorder INT
);
CREATE INDEX idx_form_fields_is_deleted ON form_fields ( is_deleted );
CREATE INDEX idx_form_fields_forms_id ON form_fields ( forms_id );
CREATE INDEX idx_form_fields_fields_id ON form_fields ( fields_id );
CREATE INDEX idx_form_fields_sortorder ON form_fields ( sortorder );

