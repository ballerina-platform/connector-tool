/*
 * Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

package io.ballerina.connectortool.utils;

import io.ballerina.connectortool.exceptions.CliException;

/**
 * Resolves the pipeline logging verbosity level from the {@code -q/--quiet}
 * and {@code -v/--verbose} CLI flags.
 */
public final class LogLevelResolutionUtils {

    private LogLevelResolutionUtils() {}

    /** Pipeline logging verbosity levels. */
    public enum LogLevel {
        QUIET,
        NORMAL,
        VERBOSE
    }

    /**
     * Resolves the log level from the two mutually exclusive CLI flags.
     *
     * @param quiet   {@code true} when {@code -q/--quiet} was passed
     * @param verbose {@code true} when {@code -v/--verbose} was passed
     * @return the resolved {@link LogLevel}
     * @throws CliException if both flags are set simultaneously (exit code 2)
     */
    public static LogLevel resolve(boolean quiet, boolean verbose) {
        if (quiet && verbose) {
            throw new CliException("options -q/--quiet and -v/--verbose are mutually exclusive", 2);
        }
        if (quiet) {
            return LogLevel.QUIET;
        }
        if (verbose) {
            return LogLevel.VERBOSE;
        }
        return LogLevel.NORMAL;
    }
}
