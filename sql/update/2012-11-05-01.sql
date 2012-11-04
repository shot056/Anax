CREATE TABLE products (
    id SERIAL NOT NULL PRIMARY KEY,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    date_created TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT ('now'::TEXT)::TIMESTAMP WITH TIME ZONE,
    date_updated TIMESTAMP WITH TIME ZONE,
    date_deleted TIMESTAMP WITH TIME ZONE,
    name TEXT NOT NULL,
    price INT NOT NULL,
    description TEXT,
    sortorder INT
);
CREATE INDEX idx_products_is_deleted ON products ( is_deleted );
CREATE INDEX idx_products_name ON products ( name );
CREATE INDEX idx_products_sortorder ON products ( sortorder );

CREATE TABLE product_images (
    id SERIAL NOT NULL PRIMARY KEY,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    date_created TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT ('now'::TEXT)::TIMESTAMP WITH TIME ZONE,
    date_updated TIMESTAMP WITH TIME ZONE,
    date_deleted TIMESTAMP WITH TIME ZONE,
    products_id INT NOT NULL REFERENCES products ( id ),
    name TEXT NOT NULL,
    description TEXT,
    basename TEXT NOT NULL,
    ext TEXT NOT NULL,
    sortorder INT
);
CREATE INDEX idx_product_images_is_deleted ON product_images ( is_deleted );
CREATE INDEX idx_product_images_name ON product_images ( name );
CREATE INDEX idx_product_images_sortorder ON product_images ( sortorder );