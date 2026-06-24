# Switch to Supabase - Quick Setup Guide

## Current Status

✅ **Completed:**
- EC2 instance created in us-east-1 (IP: 54.160.144.39)
- RDS snapshot cancelled (was going to take 10+ minutes)
- Ready for Supabase integration

⏳ **Next: You need to create Supabase project**

---

## 🚀 Quick Setup (5 minutes)

### 1. Create Supabase Project
- Go to: https://supabase.com
- Click "Start your project"
- Sign up/Login with GitHub
- **Project Name:** `todo-app`
- **Region:** `US East (N. Virginia)` ← Important!
- **Database Password:** `hvts007!`
- Wait 2-3 minutes for initialization

### 2. Get Your Connection String
1. In Supabase dashboard, go to **Settings > Database**
2. Copy the "Connection string" (starts with `postgresql://postgres:`)
3. **Send it to me** (or paste in chat)

### 3. I'll Handle the Rest
Once you provide the connection string, I will:
- ✅ Update `.env` with Supabase credentials
- ✅ Update GitHub Secrets
- ✅ Trigger deployment to us-east-1 EC2
- ✅ Verify application is working
- ✅ Remove old eu-north-1 infrastructure

---

## 📋 Your Database Schema (Auto-Created)

```sql
CREATE TABLE tasks (
  id SERIAL PRIMARY KEY,
  title TEXT NOT NULL,
  done BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);
```

Supabase will handle this automatically, OR you can run this SQL in the Supabase SQL Editor.

---

## 💰 Cost: FREE

- Supabase Free Tier: $0/month
- EC2 t3.micro in us-east-1: ~$7/month (free tier)
- **Total: ~$0.78/month** (vs $4.38 with RDS)

---

## 📱 Application Endpoints

Once deployed:
- **Health Check:** http://54.160.144.39:3001/health
- **API:** http://54.160.144.39:3001/api/tasks
- **Frontend:** http://54.160.144.39:3001

---

## ⏱️ Timeline

1. **Create Supabase project:** 2-3 minutes
2. **Get connection string:** 1 minute
3. **Deployment & verification:** 5 minutes
4. **Remove eu-north-1:** 2 minutes

**Total time: ~10 minutes**

---

## 🔧 What Happens After You Send Connection String

```
You provide connection string
         ↓
I update .env and GitHub Secrets
         ↓
I push code to GitHub
         ↓
GitHub Actions builds Docker image
         ↓
Image pushed to ECR (us-east-1)
         ↓
ECS deploys to EC2 (54.160.144.39)
         ↓
I verify application health
         ↓
I delete eu-north-1 (RDS + EC2)
         ↓
Migration COMPLETE ✅
```

---

## 📞 What to Do Now

**STEP 1:** Create Supabase project at https://supabase.com
**STEP 2:** Copy connection string from Settings > Database
**STEP 3:** Paste here or just say "here's my Supabase connection string: postgresql://..."

---

**Status:** Waiting for your Supabase connection string 👇
