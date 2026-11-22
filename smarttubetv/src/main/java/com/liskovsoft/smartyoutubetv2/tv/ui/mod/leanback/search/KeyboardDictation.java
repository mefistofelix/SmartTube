package com.liskovsoft.smartyoutubetv2.tv.ui.mod.leanback.search;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.speech.SpeechRecognizer;
import android.text.Editable;
import android.text.InputType;
import android.text.TextUtils;
import android.text.TextWatcher;
import android.view.KeyEvent;
import android.view.View;
import android.view.inputmethod.EditorInfo;

import androidx.leanback.widget.SearchEditText;

import com.liskovsoft.sharedutils.helpers.Helpers;

/**
 * Voice search through the keyboard dictation, for devices without a speech recognizer (Fire TV).
 * <p>
 * Fire TV apps get no {@link SpeechRecognizer}: the remote mic belongs to Alexa, and the only way voice reaches an
 * app is the dictation of the Amazon keyboard (hold the mic while the keyboard is on screen), committed as text
 * into the focused field. The keyboard sends the voice to Alexa instead when the field asks for suggestions
 * (dictation would arrive as composing text), and it does not close on Back by itself.
 */
public final class KeyboardDictation {
    /** A dictated phrase is committed in one chunk; typing adds one character at a time. */
    private static final int MIN_DICTATED_CHARS = 3;
    private static final long SUBMIT_DELAY_MS = 1500;

    public interface Callback {
        /** The dictated text settled: run the search. */
        void onDictationDone();
        /** Back pressed in the field: close the keyboard and leave the field. */
        void onDictationBack();
    }

    private KeyboardDictation() {
    }

    /** True when the in-app speech recognition can't work and the keyboard dictation is the way to search by voice. */
    public static boolean isNeeded(Context context, boolean hasExternalRecognizer) {
        if (Helpers.isAmazonFireTVDevice()) {
            return true;
        }

        try {
            return !hasExternalRecognizer && context != null && !SpeechRecognizer.isRecognitionAvailable(context);
        } catch (RuntimeException e) {
            return false;
        }
    }

    public static void setup(SearchEditText editor, Callback callback) {
        // Same field setup as WLTV/FireBro, where the Fire TV keyboard dictation works
        editor.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        editor.setImeOptions(EditorInfo.IME_FLAG_NO_EXTRACT_UI | EditorInfo.IME_ACTION_SEARCH);
        editor.setPrivateImeOptions(null); // Google Leanback IME options ("escapeNorth,voiceDismiss")

        // IME_ACTION_SEARCH is already handled by the SearchBar (submit)

        editor.setOnPreImeKeyListener((v, keyCode, event) -> {
            if (keyCode != KeyEvent.KEYCODE_BACK) {
                return false;
            }
            if (event.getAction() == KeyEvent.ACTION_UP) {
                callback.onDictationBack();
            }
            return true;
        });

        Handler handler = new Handler(Looper.getMainLooper());
        String[] textOnFocus = {null};
        Runnable done = () -> {
            String text = editor.getText().toString();
            // The IME restores the old text when it opens: that's not a dictation
            if (editor.hasFocus() && !TextUtils.isEmpty(text.trim()) && !text.equals(textOnFocus[0])) {
                textOnFocus[0] = text;
                callback.onDictationDone();
            }
        };

        View.OnFocusChangeListener previousListener = editor.getOnFocusChangeListener();
        editor.setOnFocusChangeListener((v, focused) -> {
            handler.removeCallbacks(done);
            textOnFocus[0] = focused ? editor.getText().toString() : null;
            if (previousListener != null) {
                previousListener.onFocusChange(v, focused);
            }
        });
        editor.addTextChangedListener(new TextWatcher() {
            @Override
            public void beforeTextChanged(CharSequence s, int start, int count, int after) {
            }

            @Override
            public void onTextChanged(CharSequence s, int start, int before, int count) {
                handler.removeCallbacks(done);
                if (count >= MIN_DICTATED_CHARS && editor.hasFocus()) {
                    handler.postDelayed(done, SUBMIT_DELAY_MS);
                }
            }

            @Override
            public void afterTextChanged(Editable s) {
            }
        });
    }
}
