# إعداد Backend لدعم جميع المنصات

## المتطلبات

1. **Node.js 14+**
2. **FFmpeg** (للتحويل الصوتي)
3. **yt-dlp** (لتحميل الفيديوهات من جميع المنصات)

## تثبيت yt-dlp

### Windows:
```bash
# باستخدام pip
pip install yt-dlp

# أو تحميل من GitHub
# https://github.com/yt-dlp/yt-dlp/releases
```

### Linux/Mac:
```bash
# باستخدام pip
pip install yt-dlp

# أو باستخدام Homebrew (Mac)
brew install yt-dlp
```

### التحقق من التثبيت:
```bash
yt-dlp --version
```

## تثبيت حزم Node.js

```bash
cd backend
npm install
```

## تشغيل الـ Backend

```bash
npm start
```

## المنصات المدعومة

- ✅ **YouTube** - أفضل دعم
- ✅ **Facebook** - فيديوهات Facebook و Watch
- ✅ **Twitter/X** - تغريدات فيديو
- ✅ **Instagram** - فيديوهات و Reels
- ✅ **TikTok** - فيديوهات TikTok
- ✅ **LinkedIn** - فيديوهات LinkedIn
- ✅ **Vimeo** - فيديوهات Vimeo
- ✅ **والمزيد...** - أي منصة يدعمها yt-dlp

## ملاحظات

- تأكد أن yt-dlp محدث: `yt-dlp -U`
- بعض الفيديوهات قد تكون محمية بحقوق خاصة
- Facebook و Instagram قد يتطلبان تسجيل الدخول لبعض الفيديوهات

