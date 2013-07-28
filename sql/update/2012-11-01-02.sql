CREATE TABLE applicants (
    id SERIAL PRIMARY KEY NOT NULL,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    date_created TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT ('now'::TEXT)::TIMESTAMP WITH TIME ZONE,
    date_updated TIMESTAMP WITH TIME ZONE,
    date_deleted TIMESTAMP WITH TIME ZONE,
    email TEXT NOT NULL
);
CREATE INDEX idx_applicants_is_deleted ON applicants ( is_deleted );
CREATE INDEX idx_applicants_date_created ON applicants ( date_created );
CREATE INDEX idx_applicants_email ON applicants ( email );

CREATE TABLE applicant_form (
    id SERIAL PRIMARY KEY NOT NULL,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    date_created TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT ('now'::TEXT)::TIMESTAMP WITH TIME ZONE,
    date_updated TIMESTAMP WITH TIME ZONE,
    date_deleted TIMESTAMP WITH TIME ZONE,
    applicants_id INT NOT NULL REFERENCES applicants ( id ),
    forms_id INT NOT NULL REFERENCES forms ( id )
);
CREATE INDEX idx_applicant_form_is_deleted ON applicant_form ( is_deleted );
CREATE INDEX idx_applicant_form_date_created ON applicant_form ( date_created );
CREATE INDEX idx_applicant_form_applicants_id ON applicant_form ( applicants_id );
CREATE INDEX idx_applicant_form_forms_id ON applicant_form ( forms_id );

CREATE TABLE applicant_data (
    id SERIAL PRIMARY KEY NOT NULL,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    date_created TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT ('now'::TEXT)::TIMESTAMP WITH TIME ZONE,
    date_updated TIMESTAMP WITH TIME ZONE,
    date_deleted TIMESTAMP WITH TIME ZONE,
    applicant_form_id INT NOT NULL REFERENCES applicant_form ( id ),
    applicants_id INT NOT NULL REFERENCES applicants ( id ),
    forms_id INT NOT NULL REFERENCES forms ( id ),
    fields_id INT NOT NULL REFERENCES fields ( id ),
    text TEXT,
    field_options_id INT REFERENCES field_options ( id )
);
CREATE INDEX idx_applicant_data_is_deleted ON applicant_data ( is_deleted );
CREATE INDEX idx_applicant_data_applicants_id ON applicant_data ( applicants_id );
CREATE INDEX idx_applicant_data_applicant_form_id ON applicant_data ( applicant_form_id );
CREATE INDEX idx_applicant_data_forms_id ON applicant_data ( forms_id );
CREATE INDEX idx_applicant_data_fields_id ON applicant_data ( fields_id );
CREATE INDEX idx_applicant_data_text ON applicant_data ( text );
CREATE INDEX idx_applicant_data_field_options_id ON applicant_data ( field_options_id );


