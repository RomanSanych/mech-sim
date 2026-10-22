# -*- coding: utf-8 -*-
import json
path = r"C:\Users\RomanSanych\.cursor\projects\d-mech-sim\agent-transcripts\c54037a8-ffb5-4169-8bad-c9f3054d9e6e\c54037a8-ffb5-4169-8bad-c9f3054d9e6e.jsonl"
out = r"C:\Users\RomanSanych\.cursor\projects\d-mech-sim\agent-tools\user_msgs.txt"
keys = ["Фаски", "сбоку", "сверху", "заужен", "сплошной", "иглу", "винт", "подсветк", "CSG", "дроссел", "канал"]
with open(path, "r", encoding="utf-8") as f, open(out, "w", encoding="utf-8") as w:
	for i, line in enumerate(f, 1):
		if not any(k in line for k in keys):
			continue
		try:
			o = json.loads(line)
		except Exception:
			continue
		s = json.dumps(o, ensure_ascii=False)
		if "<user_query>" in s:
			a = s.find("<user_query>")
			b = s.find("</user_query>")
			if a >= 0 and b > a:
				w.write("=== line %d ===\n" % i)
				w.write(s[a : b + 14] + "\n\n")
			continue
		msg = o.get("message")
		if isinstance(msg, dict) and msg.get("role") == "user":
			c = msg.get("content")
			if isinstance(c, list):
				for p in c:
					if isinstance(p, dict) and p.get("type") == "text":
						t = p.get("text", "")
						if any(k in t for k in keys):
							w.write("=== line %d ===\n" % i)
							w.write(t[:2500] + "\n\n")
print("done")
