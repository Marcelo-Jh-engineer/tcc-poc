package br.edu.poc.resource;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.math.BigDecimal;
import java.time.OffsetDateTime;

@Entity
@Table(name = "products")
public class ProductEntity extends PanacheEntityBase {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    public Long id;

    @Column(name = "owner_subject", nullable = false, length = 255)
    public String ownerSubject;

    @Column(name = "owner_username", nullable = false, length = 255)
    public String ownerUsername;

    @Column(nullable = false, length = 120)
    public String name;

    @Column(nullable = false, precision = 12, scale = 2)
    public BigDecimal price;

    @Column(nullable = false, length = 16)
    public String icon;

    @Column(nullable = false, length = 80)
    public String category;

    @Column(name = "created_at", nullable = false)
    public OffsetDateTime createdAt;
}
