<div align="center">

# MoonCaptcha

**基于 MoonBit 的行为验证码组件**

**A Behavioral CAPTCHA Component Based on MoonBit**

![Language](https://img.shields.io/badge/language-MoonBit-9B4DFF)
![License](https://img.shields.io/badge/license-MIT-blue)
![Status](https://img.shields.io/badge/status-WIP-orange)
![PRs](https://img.shields.io/badge/PRs-welcome-brightgreen)

**[简体中文](./README.md) · English**

</div>

---

### Introduction

MoonCaptcha is a behavioral CAPTCHA component based on [MoonBit](https://www.moonbitlang.com/). It aims to port the behavioral CAPTCHA capabilities of [AJ-Captcha](https://gitee.com/belief-team/captcha) to the MoonBit ecosystem, providing a reusable interactive human-verification solution for web applications, mobile apps, admin consoles, open platforms, and all kinds of business APIs.

Traditional image CAPTCHAs force users to recognize and type in distorted characters, which is costly and frustrating. MoonCaptcha uses behavioral verification instead: users complete verification simply by sliding a puzzle piece into place, or by clicking characters on an image in the prompted order — no typing required. The frontend collects user behavior and interaction results, while the backend performs secondary validation of the CAPTCHA token, the answer, its validity period, and the request context before returning the final verification result.

In addition to behavioral CAPTCHAs, MoonCaptcha retains the classic image CAPTCHA for scenarios where script execution is unavailable, accessibility is required, embedded environments are restricted, or the business still relies on traditional character-based verification. The project will also offer both popup and embedded UI integration modes, so the same verification logic can fit login dialogs, form pages, standalone verification pages, and mobile interfaces.

### Key Features

**🧩 Multiple Verification Modes**

- **Slide Puzzle**: drag the slider until the puzzle piece aligns with the gap in the background image;
- **Text Click**: click the characters on the image in the prompted order;
- **Image CAPTCHA** (retained): for scenarios without script execution, with accessibility needs, in restricted embedded environments, or where the business still depends on traditional character verification.

**🪟 Two UI Integration Modes**

- **Popup**: triggered by a click and presented as a floating layer, ideal for login dialogs;
- **Embedded**: rendered directly inside a form page, ideal for sign-up and comment forms;
- One set of verification logic that adapts to login dialogs, form pages, standalone verification pages, and mobile interfaces.

**🔐 Secure Secondary Validation**

- CAPTCHAs are generated on the server side; frontend interaction results serve only as validation input;
- CAPTCHA tokens are single-use, guarding against replay attacks;
- Answers, validity periods, and request contexts are all validated — frontend results are never trusted blindly.

**🚀 Advantages of the MoonBit Ecosystem**

- Core verification logic is implemented in MoonBit and compiles to multiple targets including WASM / JS / Native;
- The same core code can be reused across browsers, servers, and edge environments, reducing multi-platform integration costs.

### How It Works

```mermaid
sequenceDiagram
    autonumber
    participant C as Frontend (Client)
    participant S as Backend (Server / MoonCaptcha)

    C->>S: Request a CAPTCHA
    S-->>C: Return background image, puzzle/click data, and CAPTCHA token
    C->>C: User completes the slide/click interaction; behavior is collected
    C->>S: Submit interaction result + CAPTCHA token
    S->>S: Secondary validation: token, answer, validity period, request context
    S-->>C: Return the verification result
    Note over C,S: On success, the business flow continues
```

1. The business frontend requests a CAPTCHA from the business backend;
2. MoonCaptcha generates the background image and puzzle / click data, and returns a single-use CAPTCHA token;
3. The user completes the slide or click interaction while the frontend collects the result (e.g. sliding distance, click coordinates);
4. The frontend submits the interaction result together with the CAPTCHA token to the backend;
5. The backend performs secondary validation: token validity, answer matching, validity period, and request context;
6. Once validated, the verification result is returned and the business flow continues.

### Status & Roadmap

> 🚧 MoonCaptcha is currently in the design and planning stage. APIs and module boundaries are not yet finalized — discussions via Issues are welcome.

| Capability | Status |
| --- | --- |
| Slide puzzle verification (validation flow + generation logic) | 🔄 In progress (core logic implemented & tested) |
| Text click verification (point layout + per-point validation) | 🔄 In progress (core logic implemented & tested) |
| Image CAPTCHA | 🚧 Planned |
| Popup / embedded UI | 🚧 Planned |
| Backend secondary-validation API | ✅ Core implemented (get/check/verification flow with protocol-compatible layer) |
| Documentation & examples | 🔄 In progress ([source analysis](docs/aj-captcha-analysis.md) / [migration design](docs/migration-design.md) published) |

See [docs/migration-design.md](docs/migration-design.md) §5 for milestone details.

### Quick Start

The project is still under development and no stable release is available yet. Installation instructions, API documentation, and integration examples will ship with the first usable release — stay tuned.

Meanwhile, you can try out the full flow of both behavioral CAPTCHA modes through the web login demo under `demo/` (see [demo/README.md](demo/README.md)):

```bash
node demo/server.js
# → http://localhost:3000
```

### Related Projects

- [AJ-Captcha](https://gitee.com/belief-team/captcha) — the upstream project this work ports from; behavioral CAPTCHA (slide puzzle, text click)
- [MoonBit](https://www.moonbitlang.com/) / [MoonBit Docs](https://docs.moonbitlang.com/) — the language MoonCaptcha is built with

### Contributing

Issues and pull requests are welcome!

1. Fork this repository and create your branch;
2. Commit your changes;
3. Open a pull request.

### License & Acknowledgements

- This project is licensed under the [MIT License](./LICENSE);
- Thanks to [AJ-Captcha (anji-plus/captcha)](https://gitee.com/belief-team/captcha) (Apache-2.0) for the design inspiration and the foundation for this port.
