<div dir="rtl">

# راه‌اندازی `Hermes Agent` با `9Router` روی سرور اوبونتو

[English](README.md) | **فارسی**

آموزش گام‌به‌گام برای اجرای یک دستیار هوش مصنوعی همیشه‌فعال روی سرور لینوکسی شخصی، دسترسی به آن از طریق `Telegram` و راه‌اندازی داشبورد وب روی دامنه اختصاصی.

- **[Hermes Agent](https://github.com/NousResearch/hermes-agent)**: ایجنت هوش مصنوعی متن‌باز (ساخته `Nous Research`، لایسنس `MIT`)
- **[9Router](https://github.com/decolua/9router)**: روتر و پروکسی متن‌باز و سازگار با `OpenAI` همراه با داشبورد وب
- **[Caddy](https://caddyserver.com/)**: `reverse proxy` با `HTTPS` خودکار

> **سلب مسئولیت:** این راهنما غیررسمی و از طرف جامعه کاربری است و ارتباطی با `Nous Research`، `9Router` یا `Caddy` ندارد. سهمیه‌های رایگان مدل‌ها را ارائه‌دهندگان شخص ثالث می‌دهند و هر زمان ممکن است تغییر کنند یا حذف شوند. رعایت شرایط استفاده هر ارائه‌دهنده با خود شماست.

---

## فهرست مطالب

1. [نحوه کار](#۱-نحوه-کار)
2. [پیش‌نیازها](#۲-پیشنیازها)
3. [آماده‌سازی سرور](#۳-آمادهسازی-سرور)
4. [نصب 9Router](#۴-نصب-9router)
5. [انتشار داشبورد با HTTPS](#۵-انتشار-داشبورد-با-https)
6. [تنظیم 9Router](#۶-تنظیم-9router)
7. [نصب Hermes Agent](#۷-نصب-hermes-agent)
8. [اتصال Telegram](#۸-اتصال-telegram)
9. [چک‌لیست امنیتی](#۹-چکلیست-امنیتی)
10. [رفع مشکل](#۱۰-رفع-مشکل)
11. [نگهداری](#۱۱-نگهداری)

---

## ۱. نحوه کار

</div>

```
Telegram  <-->  Hermes Agent  -->  9Router (127.0.0.1:20128)  -->  AI providers
                                        ^
                       Caddy (HTTPS) ---+   https://ai.example.com/dashboard
```

<div dir="rtl">

- `Hermes` از طریق `localhost` و با استفاده از `API` سازگار با `OpenAI` به `9Router` متصل می‌شود.
- `9Router` اطلاعات اتصال و کلیدهای API ارائه‌دهندگان را نگه می‌دارد و در صورت نیاز می‌تواند به مدل جایگزین برود (`fallback`).
- `Caddy` درخواست‌های HTTPS را به سرویس وب `9Router` هدایت می‌کند. چون این سرویس ممکن است مسیرهای API را هم ارائه کند، دامنه عمومی باید با یک لایه احراز هویت اضافی محافظت شود (در نمونه زیر از احراز هویت پایه Caddy استفاده می‌کنیم). پورت `9Router` باید فقط روی `127.0.0.1` گوش دهد و هرگز مستقیماً به اینترنت باز نشود.

## ۲. پیش‌نیازها

| مورد | توضیح |
| --- | --- |
| سرور | اوبونتو (آزمایش‌شده روی Ubuntu 26.04 LTS)، دسترسی `root` یا `sudo`، حداقل پیشنهادی: ۲ گیگابایت RAM |
| دامنه | یک دامنه یا زیردامنه که کنترلش دست شماست (مثال: `ai.example.com`) |
| حساب Telegram | برای ساخت ربات با `@BotFather` |
| شبکه | سرور به `github.com` و ارائه‌دهندگان هوش مصنوعی دسترسی داشته باشد |

## ۳. آماده‌سازی سرور

</div>

```bash
apt update && apt upgrade -y
apt install -y curl git ufw openssl
```

<div dir="rtl">

فایروال را تنظیم کنید. **ابتدا پورت `SSH` را مجاز کنید**؛ در غیر این صورت ممکن است دسترسی راه دور خودتان را قطع کنید:

</div>

```bash
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
ufw status
```

<div dir="rtl">

## ۴. نصب 9Router

**۴.۱ نصب `Node.js` (نسخه ۲۰ یا بالاتر)**

</div>

```bash
apt install -y nodejs npm
node -v
node -e 'const [major] = process.versions.node.split(".").map(Number); if (major < 20) { console.error("Node.js 20+ is required; install a supported Node.js release before continuing."); process.exit(1); }'
```

<div dir="rtl">

اگر بررسی نسخه خطا داد، با بسته پیش‌فرض اوبونتو ادامه ندهید؛ ابتدا طبق راهنمای رسمی Node.js، نسخه پشتیبانی‌شده ۲۰ یا بالاتر را برای نسخه اوبونتوی خود نصب کنید.

**۴.۲ نصب `9Router`**

</div>

```bash
npm install -g 9router
which 9router
```

<div dir="rtl">

**۴.۳ ساخت فایل تنظیمات** (گذرواژه‌ها و کلیدهای محرمانه به‌صورت تصادفی تولید می‌شوند):

</div>

```bash
mkdir -p /etc/9router /var/lib/9router
cat > /etc/9router/env <<EOF
PORT=20128
NODE_ENV=production
DATA_DIR=/var/lib/9router
INITIAL_PASSWORD=$(openssl rand -base64 18 | tr -d '/+=')
JWT_SECRET=$(openssl rand -hex 32)
API_KEY_SECRET=$(openssl rand -hex 32)
MACHINE_ID_SALT=$(openssl rand -hex 16)
REQUIRE_API_KEY=true
AUTH_COOKIE_SECURE=true
EOF
chmod 600 /etc/9router/env
```

<div dir="rtl">

**۴.۴ ساخت سرویس `systemd`**

> `9Router` متغیر محیطی `HOSTNAME` را نادیده می‌گیرد و بدون گزینه `--host` روی `0.0.0.0` (عمومی) بالا می‌آید. همیشه گزینه‌های زیر را بدهید.

</div>

```bash
cat > /etc/systemd/system/9router.service <<'EOF'
[Unit]
Description=9Router
After=network.target

[Service]
EnvironmentFile=/etc/9router/env
ExecStart=/usr/bin/env 9router --host 127.0.0.1 --port 20128 --no-browser --skip-update --log
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now 9router
```

<div dir="rtl">

**۴.۵ بررسی**

</div>

```bash
systemctl status 9router --no-pager | head -n 8
ss -tlnp | grep 20128
```

<div dir="rtl">

خروجی `ss` باید `127.0.0.1:20128` را نشان بدهد، **نه** `0.0.0.0:20128`. سرویس وب 9Router ممکن است علاوه بر داشبورد، مسیرهای API را هم ارائه کند؛ بنابراین دامنه عمومی را با لایه احراز هویت اضافی محافظت کنید. درگاه 9Router نباید مستقیماً در اینترنت باز باشد.

## ۵. انتشار داشبورد با HTTPS

**۵.۱ رکورد `DNS`:** یک رکورد `A` برای زیردامنه بسازید که به `IP` عمومی سرور اشاره کند. اگر از `Cloudflare` استفاده می‌کنید، فعلاً حالت **DNS only** (ابر خاکستری) بگذارید. بررسی کنید:

</div>

```bash
getent hosts ai.example.com
```

<div dir="rtl">

**۵.۲ نصب `Caddy` و افزودن لایه احراز هویت** (دامنه را عوض کنید):

ابتدا یک هش رمز بسازید. از رمز طولانی و منحصربه‌فرد استفاده کنید و رمز داشبورد 9Router را دوباره به کار نبرید:

</div>

```bash
caddy hash-password --plaintext 'REPLACE_WITH_A_LONG_UNIQUE_PASSWORD'
```

<div dir="rtl">

خروجی هش را کپی کنید و در پیکربندی زیر، مقدار `PASTE_HASH_OUTPUT_HERE` را با هش کامل جایگزین کنید. **پیش از بارگذاری مجدد Caddy حتماً این جایگزینی را انجام دهید.**

</div>

```bash
apt install -y caddy
cat > /etc/caddy/Caddyfile <<'EOF'
ai.example.com {
    basic_auth {
        admin PASTE_HASH_OUTPUT_HERE
    }
    reverse_proxy 127.0.0.1:20128
}
EOF
caddy validate --config /etc/caddy/Caddyfile
systemctl reload caddy || systemctl restart caddy
```

<div dir="rtl">

این تنظیم، سرویس وب عمومی را با یک لایه احراز هویت دوم محافظت می‌کند. اتصال محلی Hermes به `http://127.0.0.1:20128/v1` تحت تأثیر قرار نمی‌گیرد. اگر به دسترسی API از راه دور نیاز دارید، به‌جای حذف این محافظت، مسیر دسترسی جداگانه و احراز هویت‌شده طراحی کنید.

**۵.۳ بررسی:** `Caddy` گواهی `TLS` را خودکار می‌گیرد (تا یک دقیقه طول می‌کشد):

</div>

```bash
curl -sI https://ai.example.com | head -n 5
```

<div dir="rtl">

باید `HTTP/2 307` با `location: /dashboard` ببینید.

## ۶. تنظیم 9Router

1. رمز اولیه داشبورد را بخوانید (**هرگز به اشتراک نگذارید**):
   </div>

   ```bash
   grep INITIAL_PASSWORD /etc/9router/env
   ```

   <div dir="rtl">

2. آدرس `https://ai.example.com/dashboard` را باز کنید و وارد شوید.
3. **رمز را عوض کنید** (در تنظیمات داشبورد).
4. از بخش **Providers** دست‌کم یک ارائه‌دهنده وصل کنید. بعضی نیاز به ثبت‌نام ندارند و بعضی کلید `API` یا ورود `OAuth` می‌خواهند.
5. اختیاری: یک **Combo** بسازید (فهرستی نام‌دار از مدل‌ها با `fallback` خودکار). نام آن را می‌توانید در `Hermes` به‌عنوان نام مدل بدهید.
6. از بخش مدیریت کلیدهای `API` یک کلید بسازید.
7. کلید را از روی سرور تست کنید. `read -rs KEY` را بزنید، کلید را بچسبانید و `Enter` کنید، بعد:
   </div>

   ```bash
   curl -s http://127.0.0.1:20128/v1/models -H "Authorization: Bearer $KEY"
   ```

   <div dir="rtl">

8. مطمئن شوید احراز هویت واقعاً اعمال می‌شود. این درخواست **بدون** کلید باید رد شود:
   </div>

   ```bash
   curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:20128/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"model":"YOUR_MODEL","messages":[{"role":"user","content":"hi"}]}'
   ```

   <div dir="rtl">

   انتظار می‌رود `401` یا `403` بگیرید. اگر `200` گرفتید، `endpoint` را بدون احراز هویت فرض کنید و آن را فقط روی `127.0.0.1` نگه دارید.

## ۷. نصب Hermes Agent

</div>

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
source ~/.bashrc
hermes --version
```

<div dir="rtl">

در راه‌اندازی اولیه، از شما درباره روش پیکربندی سؤال می‌شود. گزینه **Full setup** را انتخاب کنید، نه گزینه سریع `Nous Portal`؛ سپس مقادیر زیر را وارد کنید:

| سؤال ویزارد | پاسخ |
| --- | --- |
| Provider | **Custom endpoint** (نزدیک انتهای فهرست) |
| Base URL | `http://127.0.0.1:20128/v1` |
| API key | کلید `9Router` از مرحله ۶ |
| API compatibility mode | `2` یعنی "Chat Completions" |
| Model | نام "combo" یا مدل شما در `9Router` |
| Context length | خالی بگذارید (تشخیص خودکار) |
| Display name | هر چیزی، مثلاً `9Router` |
| Terminal backend | `Local` (به [چک‌لیست امنیتی](#۹-چکلیست-امنیتی) نگاه کنید) |
| Messaging platforms | فعلاً رد کنید |

انتخاب مدل را هر زمان با `hermes model` می‌توانید دوباره انجام دهید. تست کنید:

</div>

```bash
hermes
```

<div dir="rtl">

یک پیام کوتاه بفرستید. اگر پاسخ دریافت کردید، اتصال `Hermes` و `9Router` برقرار است. با `/exit` خارج شوید.

## ۸. اتصال Telegram

1. در `Telegram` با `@BotFather` گفتگو کنید، `/newbot` را بفرستید و مراحل را دنبال کنید. **توکن ربات** را ذخیره کنید.
2. با `@userinfobot` گفتگو کنید تا **شناسه عددی** حسابتان را بگیرید.
3. روی سرور:
   </div>

   ```bash
   hermes gateway setup
   ```

   <div dir="rtl">

   گزینه **Telegram** را با `Space` انتخاب کنید، توکن را بچسبانید و هنگام پرسیدن کاربران مجاز، شناسه عددی خودتان را بدهید.

4. سرویس پس‌زمینه را بررسی کنید:
   </div>

   ```bash
   hermes gateway status
   ```

   <div dir="rtl">

   این راه‌انداز یک سرویس کاربری `systemd` نصب و قابلیت `linger` را فعال می‌کند؛ در نتیجه سرویس پس از خروج از نشست کاربر یا راه‌اندازی مجدد سرور نیز اجرا می‌ماند.

5. در `Telegram` به ربات پیام بدهید.

## ۹. چک‌لیست امنیتی

- [ ] `9Router` فقط روی `127.0.0.1` گوش می‌دهد (`ss -tlnp | grep 20128`).
- [ ] فایروال فقط پورت‌های ۲۲، ۸۰ و ۴۴۳ را باز گذاشته است.
- [ ] رمز داشبورد از رمز اولیه عوض شده است.
- [ ] درخواست بدون کلید `API` رد می‌شود (مرحله ۶.۸).
- [ ] ربات `Telegram` فقط به شناسه شما اجازه می‌دهد.
- [ ] اسرار (کلید، توکن، رمز) هرگز در گفتگو، اسکرین‌شات، `issue` یا `commit` قرار نمی‌گیرند. **اگر کلید یا رمزی لو رفت، آن را حذف و یکی جدید بسازید.** بعد از عوض کردن کلید در `Hermes`:
  </div>

  ```bash
  read -rs NEWKEY
  hermes config set HERMES_CUSTOM_127_0_0_1_20128_API_KEY "$NEWKEY"
  hermes gateway restart
  unset NEWKEY
  ```

  <div dir="rtl">

  (نام متغیر را ویزارد هنگام ذخیره کلید نشان می‌دهد.)

- [ ] با `terminal backend` از نوع `Local`، ایجنت دستورها را مستقیم روی سرور و با کاربری که `Hermes` را اجرا می‌کند اجرا می‌کند. یک کاربر غیر `root` اختصاصی بسازید و ایزوله‌سازی را در نظر بگیرید:
  </div>

  ```bash
  hermes config set terminal.backend docker
  ```

  <div dir="rtl">

  پیش از تأیید هر درخواست اجرای دستور، محتوای آن را با دقت بررسی کنید.

## ۱۰. رفع مشکل

| علامت | علت و راه‌حل |
| --- | --- |
| `9Router` مدام ری‌استارت می‌شود و `Exiting...` می‌نویسد | با `--host 127.0.0.1 --port 20128 --no-browser --skip-update` اجرا کنید (مرحله ۴.۴). |
| `9Router` روی `IP` عمومی در دسترس است | گزینه `--host` نیست. فایل سرویس را اصلاح و `systemctl daemon-reload && systemctl restart 9router` بزنید. |
| نصب `Hermes` بعد از `Cloning` گیر کرده | معمولاً فقط ساکت است. چند دقیقه صبر کنید. با `git clone --progress --depth 1 https://github.com/NousResearch/hermes-agent.git /tmp/t` تست کنید و بعد `/tmp/t` را پاک کنید. |
| `hermes: command not found` | `source ~/.bashrc` بزنید یا شل جدید باز کنید. |
| `Caddy` گواهی نمی‌گیرد | رکورد `DNS`، باز بودن پورت‌های ۸۰ و ۴۴۳ و نبودن پروکسی `CDN` را چک کنید. `journalctl -u caddy -n 50` را بخوانید. |
| ویزارد قبل از ساخت `9Router` کلید می‌خواهد | یک مقدار موقت بدهید و بعد از ساخت کلید واقعی، `hermes model` را اجرا کنید. |
| گفتگوهای طولانی خطای context می‌دهند | پنجره را کوچک‌تر کنید: `hermes config set model.context_length 65536` (حداقل لازم برای `Hermes` برابر ۶۴ هزار توکن است). |
| ربات `Telegram` جواب نمی‌دهد | `hermes gateway status` و `journalctl --user -u hermes-gateway -n 30 --no-pager` را اجرا کنید. توکن و شناسه کاربر را چک کنید. |
| مشکلات دیگر `Hermes` | `hermes doctor` |

## ۱۱. نگهداری و به‌روزرسانی

</div>

```bash
hermes update                      # update Hermes
npm update -g 9router              # update 9Router, then: systemctl restart 9router
systemctl status 9router           # service health
journalctl -u 9router -n 50        # 9Router logs
hermes gateway restart             # restart the Telegram gateway
apt update && apt upgrade -y       # system updates
```

<div dir="rtl">

---

## مشارکت

از ثبت `issue` و ارسال `pull request` استقبال می‌کنیم. لطفاً هرگز `IP`، دامنه، توکن یا رمز واقعی را در گزارش‌ها نگذارید.

## لایسنس

مستندات تحت لایسنس `MIT` منتشر می‌شود؛ متن مجوز در فایل [`LICENSE`](LICENSE) قرار دارد. ابزارهای نام‌برده‌شده لایسنس مخصوص خودشان را دارند.

</div>