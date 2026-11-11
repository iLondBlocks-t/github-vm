# github-vm — MacRDP

## التشغيل

يعمل `.github/workflows/macrdp.yml` على `macos-latest` عند تشغيله يدوياً من **GitHub → Actions → MacRDP → Run workflow**. يستخدم GitHub Secret واحداً فقط: `NGROK_AUTH_TOKEN`. لا يطلب `MACOS_USER_PASSWORD` أو `VNC_PASSWORD` أو `TAILSCALE_AUTHKEY` أو أي Secret إضافي، ولا يقبل كلمة مرور كمدخل workflow. المهلة محددة بثلاث ساعات.

يهيئ `mac/start.sh` حساب macOS الموجود على الـrunner فقط، ويقصر Remote Management عليه، ثم يولّد كلمة مرور VNC عشوائية من 8 أحرف. لا يطبع كلمة المرور في Logs أو Summary. يظهر في Summary عنوان Ngrok والمنفذ واسم حساب macOS المصرح به، إضافة إلى حمولة مشفرة بكلمة مرور التشغيل باستخدام مفتاح مشتق من `NGROK_AUTH_TOKEN`.

لاسترجاع كلمة المرور بأمان، نزّل المستودع إلى جهاز موثوق يحتوي Node.js، ثم شغّل `bash mac/login.sh`. أدخل Ngrok token عند الطلب؛ الإدخال مخفي محلياً ولا يُرسل إلى GitHub أو هذه المحادثة. بعد ذلك الصق الحمولة المشفرة كاملة من Summary. تُطبع كلمة المرور محلياً فقط. لا تستخدم الحمولة المشفرة كأنها كلمة المرور ولا تشارك قيمة الرمز.

في تطبيق VNC على Android أدخل مضيف Ngrok والمنفذ الظاهرين في Summary. مصادقة VNC legacy تكون بكلمة المرور فقط؛ اسم حساب macOS الظاهر هو الحساب الذي منحناه صلاحيات Remote Management، وقد لا يطلبه تطبيق VNC. لا تُدخل كلمة مرور macOS.

## ما الذي نتحقق منه

قبل تشغيل النفق، يجرب السكربت إعداد Apple Remote Management وVNC legacy ثم يتأكد من استماع المنفذ 5900 ومن تفاوض RFB محلياً. وبعد فتح النفق، يستخرج العنوان من Ngrok Agent API ويتحقق من أن اتصالاً عبر العنوان العام يصل إلى مصافحة RFB ومصادقة VNC legacy. لا يعلن `ONLINE`: يكتب `VNC_ENDPOINT_VERIFIED` فقط، لأن تسجيل دخول فعلي من Android والتحكم التفاعلي لا يمكن إثباتهما من الـrunner نفسه. إذا رفض macOS الإعداد أو لم ينجح أي اختبار، يفشل التشغيل ولا يعرض بيانات اتصال على أنها صالحة.

يبقى الـrunner والنفق عاملين ما دامت المهمة قيد التشغيل، بحد أقصى 180 دقيقة، ويُنهي السكربت Ngrok وRemote Management عند انتهاء المهمة أو إلغائها. عنوان TCP يتغير بين التشغيلات.

## القيود الأمنية والتوافقية

`kickstart` قد لا يمكّن Screen Sharing على نسخ macOS الحديثة، وقد يكون التحكم عبر الإعدادات المدعومة محدوداً. الاختبار الفعلي على `macos-latest` هو الفيصل؛ لا تُفترض النتيجة من نجاح الأمر وحده. راجع [توثيق Apple لتمكين Remote Management](https://support.apple.com/ro-md/guide/remote-desktop/apd8b1c65bd/mac).

كلمة المرور مولدة بطول 8 أحرف بالضبط لأن الإعداد القديم كان يقتطع كل ما بعد الحرف الثامن؛ السكربت لا يقتطع كلمة مرور أطول. هذا قيد في مصادقة VNC legacy وليس بديلاً عن كلمة مرور طويلة حديثة. كما تحذر Apple من أن بعض برامج VNC الخارجية لا تشفر ضغطات المفاتيح أو بيانات الشاشة. نفق Ngrok TCP لا يثبت تشفير VNC طرفاً إلى طرف؛ لا تستخدم الجلسة مع بيانات حساسة، وأوقف التشغيل بعد الانتهاء. راجع [تحذير Apple بشأن وصول VNC](https://support.apple.com/guide/remote-desktop/virtual-network-computing-access-and-control-apde0dd523e/mac).

حساب Ngrok المجاني يتطلب بطاقة صالحة لاستخدام TCP endpoints، وتذكر Ngrok أنها لا تُخصم. هذا المستودع لا يطلب منك شراء اشتراك أو إضافة Secret آخر. راجع [قيود الخطة المجانية لدى Ngrok](https://ngrok.com/docs/using-ngrok-with/minecraft).

## التدقيق السابق

كان `mac/start.sh` القديم ينزّل سكربتاً خارجياً متغيراً، وينشئ حساب `runneradmin` بمعرّف UID ثابت ومجلد منزل غير متسق، ويستخدم كلمة مرور macOS ثابتة، ويمنح Remote Management لجميع المستخدمين. كما كان يفعّل VNC legacy بكلمة ثابتة ويخزنها بإخفاء ضعيف. وكان `mac/login.sh` يطبع كلمة المرور. أزلت هذا المسار وعطّلت workflow القديم؛ لا يستخدم التنفيذ الحالي `mxschmitt/action-tmate@v2` ولا ينزّل سكربتات خارجية أثناء التشغيل.

ملف `.github/workflows/main.yml.disabled` أرشيف فقط، وGitHub Actions لا يشغله. أما `win2022.txt` فهو خارج مسار MacRDP ولم يتغير؛ يحتوي إعداد Windows منفصلاً وكلمة مرور ثابتة، فراجعه إذا كان مستخدماً.
