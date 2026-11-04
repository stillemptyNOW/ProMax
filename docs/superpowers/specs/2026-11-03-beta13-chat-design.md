# Beta 13 conversation design

ProMax gets its own default conversation interface. Familiar messaging proportions and keyboard behavior are the reference; no Telegram source code, artwork, or GPL assets are used. The current presentation remains available through Classic design. This implementation choice was delegated by the user.

The existing theme supplies every color and font. A reference dark palette is canvas #0D0D14, raised surface #1A1A26, field #262636, text #E7E0F0 and accent #CDBDFF; light mode and custom accents resolve through ColorScheme. Display uses the selected application font at 17–22px, reading text stays 16px, supporting labels use 12–14px. No new font or image dependencies are introduced.

Conversation rows become open, aligned reading lanes: avatar, two text lines, and a quiet timestamp/unread rail. Selection alone adds a rounded accent surface. Chat controls share one compact header rather than three competing pills. The composer becomes a stable writing surface with a distinct send action. Message groups use a restrained corner rhythm and keep attachment, quote, reaction, selection and timestamp behavior.

```text
avatar  Name                              time
        Message preview                 count

back  avatar Name / status         call menu

incoming message
                         outgoing message

attach  Message field / stickers       send
```

Recoloring the existing layout would be cheaper but would retain its competing shapes and fixed-height constraints. Replacing the app shell would endanger unrelated navigation and platform integrations. The chosen scope introduces new conversation layouts while retaining existing data, actions, adaptive navigation and native glass boundaries.

Implementation: persist a default-new/classic flag; add an independently testable conversation row; apply the new header/composer/message presentation behind that flag; then verify narrow screens, large text, both brightness modes, classic mode, and existing message layout tests. Glass, custom themes, iOS native surfaces and reduced motion continue to use the established rendering paths. Screenshots contain synthetic contacts and messages only.
