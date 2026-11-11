# Kıvrak Barber — Appointment Booking & Management System

A lightweight, serverless web application for barber appointment scheduling and staff management, backed by Supabase and hosted on Netlify.

---

## 🚀 Overview

This project provides a modern, fast, and responsive digital booking experience for barbershops and salons. It eliminates third-party platform fees by running completely serverless with a static frontend and a secure PostgreSQL backend.

---

## ✨ Features

### 💈 Customer Booking Portal (`index.html`)
- **Multilingual Support:** Full localization in 4 languages (Turkish, English, German, French).
- **Multi-Barber Selection:** Real-time slot availability filtered by specific barber or "First Available".
- **Self-Service Actions:** Instant appointment cancellation, coupon validation, and QR code status checks.
- **WhatsApp Integration:** Direct confirmation and calendar sync via WhatsApp message generator.

### 🛡️ Admin Dashboard (`yonetim.html`)
- **Secure Authentication:** Protected panel powered by Supabase Auth.
- **Schedule Overview:** Daily and weekly appointment tracking with barber-specific filters.
- **No-Show Tracking:** Flag clients who missed appointments with historical warnings.
- **Business Configuration:** Set working hours, break times, weekly holidays, and active staff rosters.

---

## 🛠️ Architecture & Tech Stack

- **Frontend:** HTML5, CSS3, Modern Vanilla JavaScript (zero build step, instant deployment).
- **Backend & Database:** Supabase (PostgreSQL with Row-Level Security and stored procedures).
- **Hosting:** Netlify (static CDN distribution with custom caching headers).

---

## 📦 Setup & Deployment

1. **Database Setup:** 
   Run the schema migration script (`supabase.sql`) in your Supabase SQL Editor to create tables, RPC functions, and Row-Level Security policies.
2. **Configuration:** 
   Add your public Supabase URL and anonymous key into the frontend configuration block.
3. **Deployment:** 
   Deploy the directory directly to Netlify or connect this repository for continuous deployment.

---

## 📄 License
This project is proprietary and built for Kıvrak Barber.
