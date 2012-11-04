CREATE TABLE field_options (
    id SERIAL PRIMARY KEY NOT NULL,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    date_created TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT ('now'::TEXT)::TIMESTAMP WITH TIME ZONE,
    date_updated TIMESTAMP WITH TIME ZONE,
    date_deleted TIMESTAMP WITH TIME ZONE,
    fields_id INT NOT NULL REFERENCES fields ( id ),
    name TEXT NOT NULL,
    sortorder INT
);
CREATE INDEX idx_field_options_is_deleted ON field_options ( is_deleted );
CREATE INDEX idx_field_options_fields_id ON field_options ( fields_id );
CREATE INDEX idx_field_options_sortorder ON field_options ( sortorder );

