# github-vm — MacRDP

## الحالة الفعلية

يعمل `.github/workflows/macrdp.yml` على `macos-latest`، ويستخدم Secret واحداً فقط هو `NGROK_AUTH_TOKEN`. لكن الاختبار الفعلي على runner المستضاف فشل قبل إنشاء نفق Ngrok: لم يقدّم المنفذ المحلي 5900 مصافحة VNC حتى بعد تصحيح تسلسل `kickstart` إلى إعداد صلاحيات المستخدم ثم تفعيل الوصول وإعادة تشغيل Remote Management.

- [المحاولة الأولى](https://github.com/iLondBlocks-t/github-vm/actions/runs/43101335853): المنفذ 5900 لم يقدّم مصافحة VNC؛ لم يبدأ Ngrok.
- [المحاولة بعد تصحيح أوامر kickstart](https://github.com/iLondBlocks-t/github-vm/actions/runs/43102513872): النتيجة نفسها؛ لم يبدأ Ngrok.

لذلك لا يوجد حالياً VNC USER أو عنوان IP/منفذ أو كلمة مرور صالحة لإعطائها، ولا ينبغي تشغيل تطبيق VNC على بيانات غير موجودة. Ngrok ليس موضع الفشل: ثُبّت CLI على runner، لكن السكربت يتوقف قبل طلب النفق عندما لا يجد خدمة VNC محلية.

## سبب الحدّ والحل المدعوم

تقول Apple إن `kickstart` لا يستطيع تمكين Screen Sharing على macOS 12.1 أو أحدث، وإن تفعيله به على macOS 10.14 أو أحدث يوفّر العرض فقط؛ وتوصي باستخدام MDM لتمكين Remote Management على macOS 12.1+. راجع [توثيق Apple لـRemote Management](https://support.apple.com/ro-md/guide/remote-desktop/apd8b1c65bd/mac).

أمر Apple المدعوم هو [Enable Remote Desktop عبر MDM](https://developer.apple.com/documentation/devicemanagement/enable-remote-desktop-command). يتطلب قناة إدارة الجهاز على macOS وجهازاً خاضعاً للإشراف؛ ولا يمكن استبدال الأمر بإضافة `NGROK_AUTH_TOKEN` أو بتغيير منفذ Ngrok. GitHub-hosted runner آلة افتراضية مؤقتة جديدة لكل job، وليست جهاز Mac مُسجلاً في MDM الخاص بك. لذا لا توجد طريقة مدعومة حالياً لتمكين VNC تفاعلي على هذا الـrunner بهذه الموارد وحدها. تؤكد [إرشادات Apple لـMDM](https://support.apple.com/en-us/102024) أن الأمر يمكّن Remote Management مع خياري Observe وControl.

تجربة [MacOps على Monterey 12.1](https://macops.ca/managing-screen-sharing-in-monterey-12.1/) تشرح أن تشغيل الخدمة بطرق أقدم قد يؤدي إلى شاشة فارغة أو اتصال متوقف بسبب ضوابط TCC. لذلك لا يفعّل هذا المستودع خدمة مخفية أو يزوّر مصادقة غير مدعومة لتجاوز هذا الشرط.

## الأسرار وكلمة المرور

لا يطلب المشروع `MACOS_USER_PASSWORD` أو `VNC_PASSWORD` أو `TAILSCALE_AUTHKEY` أو أي Secret إضافي. عند نجاح فحوص VNC محلياً وعبر Ngrok فقط، يولّد `mac/start.sh` كلمة مرور VNC عشوائية من 8 أحرف، ويطبع الحمولة المشفرة فقط، وليس كلمة المرور، مع عنوان Ngrok واسم حساب macOS المصرح به. يمكن فك الحمولة محلياً عبر `bash mac/login.sh` باستخدام `NGROK_AUTH_TOKEN`؛ الإدخال مخفي ولا يُرسل إلى GitHub أو هذه المحادثة. في التشغيلين المذكورين لم تُنشأ كلمة مرور صالحة أو حمولة اتصال.

مصادقة VNC legacy تستخدم كلمة المرور فقط عادةً؛ اسم الحساب المعروض هو حساب macOS الذي جرى السماح له في Remote Management، وقد لا يطلبه تطبيق VNC. لا تُدخل كلمة مرور حساب macOS. كلمة VNC legacy محدودة بثمانية أحرف، كما تحذر Apple من أن بعض عملاء VNC الخارجيين قد لا يشفّرون ضغطات المفاتيح أو بيانات الشاشة. نفق Ngrok TCP لا يوفّر بحد ذاته تشفيراً طرفاً لطرف لبروتوكول VNC. راجع [تحذير Apple بشأن VNC](https://support.apple.com/guide/remote-desktop/virtual-network-computing-access-and-control-apde0dd523e/mac).

## متى يمكن الحصول على VNC عبر Ngrok؟

يلزم أولاً جهاز Mac تستطيع إدارته فعلياً أو إدارته عبر MDM، مع تمكين Screen Sharing والتحكم فيه بطريقة تدعمها Apple. بعد أن يستمع VNC محلياً ويجتاز فحص RFB، يستطيع Ngrok إنشاء TCP endpoint؛ حينها فقط يمكن عرض العنوان والمنفذ والحساب والحمولة المشفرة. استخدام Mac مستضاف ذاتياً أو مزوّد خدمة يوفّر Remote Desktop مُهيأ مسبقاً هو البديل العملي. لا تُنشئ Secrets إضافية لتجربة runner الحالي؛ فهي لن تفعّل خدمة الشاشة.

تذكر Ngrok أن الخطة المجانية تتطلب بطاقة صالحة لاستخدام TCP endpoints، مع عدم خصم البطاقة. راجع [قيود Ngrok TCP](https://ngrok.com/docs/using-ngrok-with/minecraft).

## التدقيق السابق

أُزيل المسار القديم الذي كان ينزّل سكربتات غير مراجعة، وينشئ حساب `runneradmin` بإعدادات ثابتة، ويستخدم كلمات مرور ثابتة ويطبع كلمة مرور VNC. workflow القديم معطّل؛ لا يستخدم المسار الحالي `mxschmitt/action-tmate@v2` ولا ينزّل سكربتات خارجية أثناء التشغيل.

ملف `.github/workflows/main.yml.disabled` أرشيف فقط، وGitHub Actions لا يشغله. أما `win2022.txt` فهو خارج مسار MacRDP ولم يتغير؛ يحتوي إعداد Windows مستقلاً وكلمة مرور ثابتة، فراجعه إذا كان مستخدماً.
