CREATE TABLE form_products (
    id SERIAL NOT NULL PRIMARY KEY,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    date_created TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT ('now'::TEXT)::TIMESTAMP WITH TIME ZONE,
    date_updated TIMESTAMP WITH TIME ZONE,
    date_deleted TIMESTAMP WITH TIME ZONE,
    forms_id INT NOT NULL REFERENCES forms ( id ),
    products_id INT NOT NULL REFERENCES products ( id ),
    sortorder INT
);
CREATE INDEX idx_form_products_is_deleted ON form_products ( is_deleted );
CREATE INDEX idx_form_products_forms_id ON form_products ( forms_id );
CREATE INDEX idx_form_products_products_id ON form_products ( products_id );
CREATE INDEX idx_form_products_sortorder ON form_products ( sortorder );


