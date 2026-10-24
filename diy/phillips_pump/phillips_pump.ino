// Насос домашней машины Филлипса: подача помпы пропорциональна объёму воды в нижнем баке,
// как в модели программы: Y = PUMP_K · уровень (economy.gd), с поправкой на масштаб времени стенда.
//
// Детали: Arduino Nano, ультразвуковой датчик HC-SR04 над нижним баком (смотрит вниз на воду),
// MOSFET-модуль (IRF520 / IRLZ44N с логическим затвором) в минусе помпы 12 В, диод на помпе,
// кнопка вкл/выкл насоса на D2 (на землю). Земли Arduino и блока 12 В соединены.
//
// Порт: 115200 бод, раз в секунду строка CSV: t_s,level_cm,water_ml,y_ml_s,pwm
// Калибровка — раздел «Сборка дома» в инструкции (F1 в программе).

// --- Подключение -------------------------------------------------------------
const int PIN_TRIG = 9;
const int PIN_ECHO = 10;
const int PIN_PUMP = 3;       // ШИМ
const int PIN_BUTTON = 2;

// --- Геометрия стенда (как в diy_rig.gd) ------------------------------------
const float SENSOR_TO_BOTTOM_CM = 20.0;  // от датчика до дна нижнего бака — измерьте линейкой
const float SUMP_AREA_CM2 = 200.0;       // дно 20 × 10 см
const float SUMP_DEAD_ML = 500.0;        // запас под помпой, в модель не входит

// --- Модель ------------------------------------------------------------------
// PUMP_K = 0,5 1/с модели, 1 с модели = 10 с стенда → 0,05 1/с стенда.
const float PUMP_K_PER_S = 0.05;

// --- Калибровка помпы --------------------------------------------------------
// PUMP_MAX_ML_S — подача при ШИМ 255 на высоту вашего щита (240 л/ч ≈ 66,7 мл/с по паспорту,
// реально меньше — измерьте мерным стаканом). PWM_MIN — ниже этого ШИМ помпа не крутится.
const float PUMP_MAX_ML_S = 66.7;
const int PWM_MIN = 60;

bool pumpOn = true;
float levelCm = 0.0;
unsigned long lastReport = 0;

float readDistanceCm() {
  digitalWrite(PIN_TRIG, LOW);
  delayMicroseconds(2);
  digitalWrite(PIN_TRIG, HIGH);
  delayMicroseconds(10);
  digitalWrite(PIN_TRIG, LOW);
  unsigned long us = pulseIn(PIN_ECHO, HIGH, 30000UL);
  if (us == 0) return -1.0;
  return us * 0.0343 / 2.0;  // скорость звука ~343 м/с при 20 °C
}

// Медиана из пяти замеров — рябь на воде и отражения дают выбросы.
float readLevelCm() {
  float v[5];
  int n = 0;
  for (int i = 0; i < 5; i++) {
    float d = readDistanceCm();
    if (d > 0) v[n++] = d;
    delay(12);
  }
  if (n == 0) return levelCm;
  for (int i = 0; i < n; i++)
    for (int j = i + 1; j < n; j++)
      if (v[j] < v[i]) { float t = v[i]; v[i] = v[j]; v[j] = t; }
  return SENSOR_TO_BOTTOM_CM - v[n / 2];
}

void setup() {
  pinMode(PIN_TRIG, OUTPUT);
  pinMode(PIN_ECHO, INPUT);
  pinMode(PIN_PUMP, OUTPUT);
  pinMode(PIN_BUTTON, INPUT_PULLUP);
  Serial.begin(115200);
  Serial.println("t_s,level_cm,water_ml,y_ml_s,pwm");
  levelCm = readLevelCm();
}

void loop() {
  static bool lastButton = HIGH;
  bool button = digitalRead(PIN_BUTTON);
  if (lastButton == HIGH && button == LOW) pumpOn = !pumpOn;
  lastButton = button;

  // Сглаживание: уровень меняется медленно, датчик шумит.
  levelCm += 0.3 * (readLevelCm() - levelCm);

  // Вода в обороте = объём над мёртвым запасом; Y = K · вода.
  float waterMl = levelCm * SUMP_AREA_CM2 - SUMP_DEAD_ML;
  if (waterMl < 0) waterMl = 0;
  float yMlS = pumpOn ? PUMP_K_PER_S * waterMl : 0.0;
  int pwm = 0;
  if (yMlS > 0.5) {
    float share = yMlS / PUMP_MAX_ML_S;
    if (share > 1) share = 1;
    pwm = PWM_MIN + (int)((255 - PWM_MIN) * share);
  }
  analogWrite(PIN_PUMP, pwm);

  unsigned long now = millis();
  if (now - lastReport >= 1000) {
    lastReport = now;
    Serial.print(now / 1000.0, 1); Serial.print(',');
    Serial.print(levelCm, 2); Serial.print(',');
    Serial.print(waterMl, 0); Serial.print(',');
    Serial.print(yMlS, 1); Serial.print(',');
    Serial.println(pwm);
  }
}
