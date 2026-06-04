# Recipe: Tkinter GUI для долгой операции (без зависаний + прогресс)

## Условия применения
Десктоп-утилита на Tkinter, которая запускает ДОЛГИЙ процесс (прошивка, сборка, деплой, конвейер шагов с подпроцессами). Окно не должно «не отвечать», нужен прогресс и понятные подтверждения.

## Суть
1. **Конвейер — в РАБОЧЕМ ПОТОКЕ, не в главном.** Если запустить долгую работу прямо в обработчике кнопки, Tk-event-loop встаёт → окно фризится на subprocess/sleep. Решение: `threading.Thread(target=worker, daemon=True).start()`.
2. **Из потока НЕЛЬЗЯ трогать Tk-виджеты напрямую.** Лог/прогресс/done → в `queue.Queue`, главный поток забирает по таймеру `root.after(120, drain)`:
   ```python
   q=queue.Queue(); log=lambda s: q.put(('log',s))
   def drain():
       try:
           while True:
               k,*rest=q.get_nowait()
               if k=='log': box.insert('end',rest[0]+'\n'); box.see('end')
               elif k=='progress': bar['value']=rest[0]; step.set(rest[1])
               elif k=='done': run_btn['state']='normal'
       except queue.Empty: pass
       root.after(120, drain)
   ```
3. **Подтверждение шага из потока** (модалку Tk звать из потока нельзя) — мост через Event:
   ```python
   ev=threading.Event(); res={}
   def confirm(prompt):           # вызывается из worker-потока
       ev.clear(); q.put(('confirm',prompt)); ev.wait(); return res['v']
   # в drain: on 'confirm' → res['v']=messagebox.askyesno(...); ev.set()
   ```
   Либо «без подтверждений» (галка) → `confirm=lambda p: True`.
4. **Прогресс**: `ttk.Progressbar(maximum=100)` + `StringVar` «Шаг X/N: …». Колбэк прогресса из конвейера → очередь.
5. **Вывод подпроцессов** читать как UTF-8: `subprocess.run(..., encoding='utf-8', errors='replace')` — иначе прогресс-бары/рамки (`█`) приходят мохибейком (`â–ˆ`) на RU-Windows (cp1252).
6. Кнопки disable на время работы, enable по `('done', ...)`.

## Антипаттерны
- ❌ Конвейер в обработчике кнопки → окно фризится, выглядит как зависшее.
- ❌ `messagebox`/`widget.config` из рабочего потока → краш/гонки Tk.
- ❌ `root.update()` в цикле вместо потока — костыль, всё равно блокирует на subprocess.
- ❌ N модалок-подтверждений на каждый шаг по умолчанию — раздражает; дай галку «без подтверждений», подтверждай один раз перед стартом.
- ❌ Читать stdout подпроцесса дефолтной локалью на RU-Windows → мохибейк юникод-символов.

## Источник
MDMy UFI-Provisioner GUI (2026-06-02): фиксы «окно подвисает» + «нет прогресс-бара» + мохибейк `â–ˆ` прогресс-бара edl.
