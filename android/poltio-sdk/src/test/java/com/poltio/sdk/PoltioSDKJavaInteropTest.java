package com.poltio.sdk;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;

import android.app.Application;
import androidx.test.core.app.ApplicationProvider;
import java.util.Collections;
import org.junit.After;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;

/**
 * Compiles against the SDK's public API exactly the way a Java host app would — static calls with
 * no {@code INSTANCE}, overloads for the Kotlin default arguments, and a lambda for the widget event
 * listener. If any of those regress, this file stops compiling.
 */
@RunWith(RobolectricTestRunner.class)
public class PoltioSDKJavaInteropTest {
    private final Application application = ApplicationProvider.getApplicationContext();

    @After
    public void tearDown() {
        PoltioTestSupport.resetSdk();
    }

    @Test
    public void publicApiIsCallableFromJava() {
        PoltioSDK.configure(application, "poltio_test_pk_java");
        PoltioSDK.configure(application, "poltio_test_pk_java", false);
        PoltioSDK.configure(application, "poltio_test_pk_java", null, PoltioLogLevel.ERROR);
        assertEquals(PoltioLogLevel.ERROR, PoltioSDK.getLogLevel());

        PoltioSDK.identify("java-user");
        assertEquals("java-user", PoltioSDK.getPuid());
        assertNotNull(PoltioSDK.getSdkId());
        assertNotNull(PoltioSDK.getVersion());

        PoltioSDK.track("view");
        PoltioSDK.track("view", Collections.singletonMap("url", "myapp://home"));

        PoltioSDK.recordPurchase("ORD-java", 12.5, "myapp://checkout/complete");
        PoltioSDK.recordPurchase(
                "ORD-java-2",
                12.5,
                "myapp://checkout/complete",
                "USD",
                Collections.singletonList(new PoltioPurchaseItem("SKU-1")));

        PoltioSDK.setOnWidgetEvent((event, data) -> { });
        PoltioSDK.setCacheTTL(60.0);
        PoltioSDK.clearCache();
        PoltioSDK.hideTrigger();
    }
}
