<!DOCTYPE html>
<html lang="bn">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>পড়ালেখা AI</title>
  <style>
    body{font-family:sans-serif;background:#f4f6fb;padding:14px;max-width:520px;margin:auto;color:#111}
    .box{background:#fff;padding:14px;border-radius:12px;box-shadow:0 4px 16px rgba(0,0,0,0.06)}
    h3{margin:0 0 10px}
    input,textarea,button{width:100%;padding:10px;margin:6px 0;border-radius:8px;border:1px solid #cbd5e1;font-size:15px;box-sizing:border-box}
    textarea{min-height:85px}
    .row{display:flex;gap:8px}
    .row button{flex:1;background:#0f766e}
    .send{background:#2563eb;color:#fff;border:none;font-weight:bold}
    .row button{color:#fff;border:none;font-weight:bold}
    #prev{max-width:130px;max-height:130px;display:none;border-radius:8px;margin-top:6px}
    #out{background:#f8fafc;padding:12px;border-radius:8px;border:1px solid #e2e8f0;margin-top:10px;white-space:pre-wrap;line-height:1.5}
  </style>
</head>
<body>
  <div class="box">
    <h3>পড়ালেখা AI</h3>
    <input type="password" id="k" placeholder="Google AI Studio API Key" />
    <textarea id="q" placeholder="প্রশ্ন লিখুন বা নিচের ভয়েস বোতামে চাপ দিন..."></textarea>

    <div class="row">
      <button type="button" onclick="startVoice()">🎤 কথা বলে লিখুন</button>
      <button type="button" onclick="clearAll()">মুছুন</button>
    </div>

    <input type="file" id="img" accept="image/*" />
    <img id="prev" alt="ছবি" />

    <button type="button" class="send" onclick="ask()">উত্তর দিন</button>
    <div id="out">প্রশ্ন বা ছবি দিলে এখানে উত্তর আসবে।</div>
  </div>

  <script>
    const k = document.getElementById('k');
    k.value = localStorage.getItem('gemini_key_clean') || '';
    k.onchange = () => localStorage.setItem('gemini_key_clean', k.value.trim());

    let b64 = null, mime = null;
    document.getElementById('img').onchange = (e) => {
      const f = e.target.files[0];
      const p = document.getElementById('prev');
      if (!f) { b64 = null; p.style.display = 'none'; return; }
      mime = f.type;
      const r = new FileReader();
      r.onload = () => { b64 = r.result.split(',')[1]; p.src = r.result; p.style.display = 'block'; };
      r.readAsDataURL(f);
    };

    function startVoice(){
      const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
      if (!SR) { alert('এই ব্রাউজারে ভয়েস টাইপিং সাপোর্ট করছে না, কিবোর্ডের মাইক ব্যবহার করুন।'); return; }
      const rec = new SR();
      rec.lang = 'bn-BD';
      rec.onresult = (ev) => {
        const txt = ev.results[0][0].transcript;
        const q = document.getElementById('q');
        q.value = (q.value ? q.value + ' ' : '') + txt;
      };
      rec.start();
    }

    function clearAll(){
      document.getElementById('q').value = '';
      document.getElementById('img').value = '';
      document.getElementById('prev').style.display = 'none';
      document.getElementById('out').textContent = 'প্রশ্ন বা ছবি দিলে এখানে উত্তর আসবে।';
      b64 = null; mime = null;
    }

    async function ask(){
      const key = k.value.trim();
      const q = document.getElementById('q').value.trim();
      const out = document.getElementById('out');
      if (!key) { alert('আগে API Key দিন।'); return; }
      if (!q && !b64) { alert('প্রশ্ন লিখুন, বলুন বা ছবি দিন।'); return; }

      out.textContent = 'উত্তর আসছে...';
      const parts = [{ text: 'সহজ বাংলায় পড়ালেখার উত্তর দাও:\n' + (q || 'ছবির প্রশ্নটির সমাধান দাও।') }];
      if (b64 && mime) parts.push({ inline_data: { mime_type: mime, data: b64 } });

      try {
        const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${encodeURIComponent(key)}`,{
          method:'POST',
          headers:{'Content-Type':'application/json'},
          body:JSON.stringify({contents:[{parts}]})
        });
        const d = await res.json();
        out.textContent = d.candidates?.[0]?.content?.parts?.map(x=>x.text).join('') || d.error?.message || 'উত্তর পাওয়া যায়নি।';
      } catch(err){
        out.textContent = 'সমস্যা হয়েছে: ' + err.message;
      }
    }
  </script>
</body>
</html>
