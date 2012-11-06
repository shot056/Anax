CREATE TABLE applicant_form_products (
    id SERIAL NOT NULL PRIMARY KEY,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    date_created TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT ('now'::TEXT)::TIMESTAMP WITH TIME ZONE,
    date_updated TIMESTAMP WITH TIME ZONE,
    date_deleted TIMESTAMP WITH TIME ZONE,
    applicants_id INT NOT NULL REFERENCES applicants ( id ),
    forms_id INT NOT NULL REFERENCES forms ( id ),
    applicant_form_id INT NOT NULL REFERENCES applicant_form ( id ),
    products_id INT NOT NULL REFERENCES products ( id ),
    number INT NOT NULL
);
CREATE INDEX idx_applicant_form_products_is_deleted ON applicant_form_products ( is_deleted );
CREATE INDEX idx_applicant_form_products_applicants_id ON applicant_form_products ( applicants_id );
CREATE INDEX idx_applicant_form_products_forms_id ON applicant_form_products ( forms_id );
CREATE INDEX idx_applicant_form_products_applicant_form_id ON applicant_form_products ( applicant_form_id );
CREATE INDEX idx_applicant_form_products_products_id ON applicant_form_products ( products_id );

