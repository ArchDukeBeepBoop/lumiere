package app.lumiere.android

import app.lumiere.android.ui.SignInField
import app.lumiere.android.ui.signInProblem
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Sign In always answers: it either goes ahead or says what's missing. */
class SignInProblemTest {
    @Test fun aMissingUserNameIsNamed() {
        assertEquals(SignInField.User, signInProblem("  ", "secret", "", needsAccount = false)?.second)
    }

    @Test fun anExistingAccountNeedsOnlyAName() {
        assertNull(signInProblem("jo", "", "", needsAccount = false))
    }

    @Test fun aNewAccountNeedsMatchingPasswords() {
        assertEquals(SignInField.Password, signInProblem("jo", "abc", "abc", needsAccount = true)?.second)
        assertEquals(SignInField.Password, signInProblem("jo", "abcd", "abce", needsAccount = true)?.second)
        assertNull(signInProblem("jo", "abcd", "abcd", needsAccount = true))
    }
}
