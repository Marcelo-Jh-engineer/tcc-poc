CREATE TABLE products (
    id BIGSERIAL PRIMARY KEY,
    owner_subject VARCHAR(255) NOT NULL,
    owner_username VARCHAR(255) NOT NULL,
    name VARCHAR(120) NOT NULL,
    price NUMERIC(12, 2) NOT NULL CHECK (price >= 0),
    icon VARCHAR(16) NOT NULL,
    category VARCHAR(80) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_products_owner_subject ON products (owner_subject);
