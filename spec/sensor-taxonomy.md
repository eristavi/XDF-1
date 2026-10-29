# XDF-1 Universal Sensor Taxonomy (USAL candidate)

**Status: design coverage only.** These **50 requested sensor types in 10 groups** are *planned compatibility targets*, not implemented electronics or verified device drivers. Sensor IDs label **logical streams**, which may outnumber physical devices (an IMU, camera or radar can expose multiple streams). Existing XDF-1 SEF has 64 logical IDs, not 64 physical connectors.

| Group | Included sensor types | Acquisition or preprocessing considerations |
| --- | --- | --- |
| 1. Motion / kinematics (8) | Accelerometer; Gyroscope; Magnetometer; IMU; Tilt Sensor; Rotary/Linear Encoder; Proximity Sensor; Presence Sensor | Timestamp and calibrate axis units; handle interrupt/pulse streams, sample-rate mismatch and encoder rollover |
| 2. Ranging / spatial (5) | Ultrasonic; Time-of-Flight; LiDAR; Radar; IR Distance | Use compact range events for low-rate devices; DMA buffers and frame/point-cloud descriptors for LiDAR/radar |
| 3. Optical / radiation (6) | CMOS/CCD Image Sensor; Ambient Light; RGB Color; UV; IR/Thermal Imager; Radiation Counter | Camera frames require dedicated payload buffers; preserve capture timing, pixel formats, calibration and radiation-count intervals |
| 4. Acoustic / vibration (4) | Microphone; Hydrophone; Piezoelectric Vibration; Seismometer | Continuous waveforms need sampling, batching and frequency-domain features; keep capture provenance |
| 5. Environment / weather (5) | Thermistor/Thermocouple; Humidity; Barometric Pressure; Anemometer; Rain/Leaf Wetness | Low-rate calibrated scalar measurements and units; periodic baseline samples |
| 6. Chemical / air quality (5) | Electrochemical Gas; NDIR Gas; Particulate Matter; VOC; Oxygen | Account for warm-up, drift, sampling intervals and safety rules independent of uncertain ML predictions |
| 7. Liquid / flow (5) | Flow Rate; Liquid Level; pH; Electrical Conductivity; Turbidity | Unit/calibration metadata; mixing high-rate pulse rates with low-rate chemistry |
| 8. Force / structure (4) | Load Cell/Strain Gauge; Flex/Bend; Torque; Crack/Displacement | Signed physical units, structural drift, peak detection and missing sample handling |
| 9. Biometric / health (5) | PPG; ECG/EKG; GSR; Enzymatic Electrochemical; EEG | Sensitive personal/health data; explicit permissions, encryption, retention limits and clinical validation where required |
| 10. Electromagnetic / wireless (3) | Hall Effect; RFID/NFC; RF Power Detector | Events, tag identifier privacy, RF environment noise, pulse timing |

## One adapter interface, multiple data planes

A future USAL driver declares its device ID, generated logical streams, firmware/version, physical interface, time base, units, calibration, maximum payload rate and QoS settings. Every output must be either a compact validated event or an immutable, externally buffered raw-payload descriptor. Do **not** make all raw payloads traverse the 96-bit SEF event port. Clock synchronization, privacy policies, and physical connector provisioning are separate system requirements.

Recommended first demonstration mix: low-rate temperature and proximity events, IMU burst, short microphone waveform and camera frames. Synthetic tests precede electrical integration.
